//  EnginePool.swift
//  Stockfish via ChessKitEngine, wrapped in an actor that serializes queries and
//  caches results — the Swift equivalent of the source's `server/core/engine.py`.
//
//  ChessKitEngine exposes a single shared response AsyncStream (one consumer), so a
//  long-lived reader task forwards responses to the actor, which resumes the
//  in-flight query when `bestmove` arrives. Analysis is fixed-depth and cached by
//  (fen, depth, multipv) so repeat calls are free and deterministic.

import Foundation
import ChessKitEngine

/// One principal variation from the engine, side-to-move relative.
public struct EngineLineResult: Sendable, Equatable {
    public let cp: Int?      // centipawns (nil if mate)
    public let mate: Int?    // mate-in-N (nil if cp)
    public let pvUCI: [String]

    public var winPercent: Double { Evaluation.winPercentFromScore(cp: cp, mate: mate) }

    /// Signed centipawns (mate -> ±mateScoreCp), matching the source `_signed_cp`.
    public var signedCp: Double {
        if let mate { return Double(mate > 0 ? GCConfig.mateScoreCp : -GCConfig.mateScoreCp) }
        return Double(cp ?? 0)
    }
}

/// Result of analysing one FEN. `lines[0]` is the best line.
public struct AnalysisResult: Sendable, Equatable {
    public let fen: String
    public let depth: Int
    public let lines: [EngineLineResult]
    public var best: EngineLineResult { lines[0] }
}

/// Errors from the engine layer.
public struct EngineError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Process-wide Stockfish engine, actor-serialized and cached.
public actor EnginePool {

    public static let shared = EnginePool()

    private let engine = Engine(type: .stockfish)
    private var started = false
    private var currentMultipv = 0
    private var cache: [Key: AnalysisResult] = [:]

    /// Accumulated info lines for the in-flight query, keyed by multipv index.
    private var currentInfos: [Int: EngineResponse.Info] = [:]
    private var currentBestMove: String?
    private var waiter: CheckedContinuation<Void, Never>?

    // A one-at-a-time gate: `analyse` suspends across `await`, which permits actor
    // reentrancy, so without this two concurrent calls would clobber `currentInfos`/
    // `waiter`. Each call holds the gate end-to-end.
    private var busy = false
    private var gateQueue: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { gateQueue.append($0) }
    }
    private func release() {
        if gateQueue.isEmpty { busy = false } else { gateQueue.removeFirst().resume() }
    }

    private struct Key: Hashable { let fen: String; let depth: Int; let multipv: Int }

    /// Path to a bundled NNUE net (in `Resources/nnue`, copied into Bundle.module).
    static func nnuePath(_ name: String) -> String? {
        Bundle.module.url(forResource: name, withExtension: "nnue", subdirectory: "nnue")?.path
            ?? Bundle.module.url(forResource: name, withExtension: "nnue")?.path
    }

    public init() {}

    /// Analyse a FEN at fixed depth. Cached and reproducible.
    public func analyse(fen: String, depth: Int = GCConfig.defaultDepth, multipv: Int = 1) async throws -> AnalysisResult {
        let mpv = max(1, multipv)
        let key = Key(fen: fen, depth: depth, multipv: mpv)
        if let cached = cache[key] { return cached }

        await acquire()
        defer { release() }
        // Re-check the cache now that we hold the gate (a concurrent call may have filled it).
        if let cached = cache[key] { return cached }

        try await ensureStarted()

        if mpv != currentMultipv {
            await engine.send(command: .setoption(id: "MultiPV", value: "\(mpv)"))
            currentMultipv = mpv
        }
        currentInfos = [:]
        await engine.send(command: .position(.fen(fen)))

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.waiter = cont
            Task { await engine.send(command: .go(depth: depth)) }
        }

        var lines: [EngineLineResult] = []
        for idx in 1...mpv {
            guard let info = currentInfos[idx], let score = info.score else { continue }
            lines.append(EngineLineResult(
                cp: score.cp.map { Int($0.rounded()) },
                mate: score.mate,
                pvUCI: info.pv ?? []
            ))
        }
        guard !lines.isEmpty else {
            throw EngineError("Engine returned no lines for \(fen)")
        }
        let result = AnalysisResult(fen: fen, depth: depth, lines: lines)
        cache[key] = result
        return result
    }

    /// Pick a move for an OPPONENT to play (used by Play mode). Optional `skill`
    /// (Stockfish "Skill Level" 0–20) makes it beatable; reset to full strength
    /// afterwards. Not cached. Returns the best-move UCI, or nil if there is none
    /// (game over / no legal move).
    public func playMove(fen: String, depth: Int = 12, skill: Int? = nil) async throws -> String? {
        await acquire()
        defer { release() }
        try await ensureStarted()

        if let skill {
            await engine.send(command: .setoption(id: "Skill Level", value: "\(max(0, min(20, skill)))"))
        }
        if currentMultipv != 1 {
            await engine.send(command: .setoption(id: "MultiPV", value: "1"))
            currentMultipv = 1
        }
        currentInfos = [:]
        currentBestMove = nil
        await engine.send(command: .position(.fen(fen)))
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.waiter = cont
            Task { await engine.send(command: .go(depth: depth)) }
        }
        let move = currentBestMove
        if skill != nil {
            await engine.send(command: .setoption(id: "Skill Level", value: "20"))  // restore
        }
        if let move, move != "(none)", move.count >= 4 { return move }
        return nil
    }

    /// Quit the engine and drop cached evals.
    public func shutdown() async {
        await engine.stop()
        started = false
        currentMultipv = 0
        cache.removeAll()
    }

    // MARK: private

    private func ensureStarted() async throws {
        if started { return }
        // coreCount 3 -> Threads = max(3-1,1) = 2 (matches source ENGINE_THREADS).
        await engine.start(coreCount: GCConfig.engineThreads + 1, multipv: 1)
        currentMultipv = 1

        // Forward the single shared response stream to this actor.
        guard let stream = await engine.responseStream else {
            throw EngineError("Engine response stream unavailable")
        }
        Task.detached { [weak self] in
            for await response in stream { await self?.handle(response) }
        }

        // Wait for the engine to finish its UCI setup loop.
        var tries = 0
        while await engine.isRunning == false {
            try await Task.sleep(nanoseconds: 20_000_000)
            tries += 1
            if tries > 250 { throw EngineError("Engine failed to start") } // ~5s
        }
        // Stockfish 17 needs an external NNUE net. chesskit-engine only looks in
        // Bundle.main (absent in tests / the package), so point EvalFile at the nets
        // we bundle in Bundle.module — works identically in tests and in the apps.
        if let big = Self.nnuePath("nn-1111cefa1111") {
            await engine.send(command: .setoption(id: "EvalFile", value: big))
        }
        if let small = Self.nnuePath("nn-37f18f62d772") {
            await engine.send(command: .setoption(id: "EvalFileSmall", value: small))
        }
        await engine.send(command: .setoption(id: "Hash", value: "\(GCConfig.engineHashMB)"))
        await engine.send(command: .isready)
        started = true
    }

    /// Receives every engine response (actor-isolated). Accumulates resolved info
    /// lines per multipv index and resumes the query on `bestmove`.
    private func handle(_ response: EngineResponse) {
        switch response {
        case let .info(info):
            guard let mpv = info.multipv, info.pv?.isEmpty == false, let score = info.score else { return }
            if score.lowerbound == true || score.upperbound == true { return }
            currentInfos[mpv] = info
        case let .bestmove(move, _):
            currentBestMove = move
            if let w = waiter { waiter = nil; w.resume() }
        default:
            break
        }
    }
}
