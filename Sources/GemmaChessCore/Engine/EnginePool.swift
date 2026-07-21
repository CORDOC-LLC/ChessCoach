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
        let result = try await runQuery(fen: fen, depth: depth, multipv: mpv)
        cache[key] = result
        return result
    }

    /// Low-skill band boundary for the Human-like opponent's weighted-sampling reply
    /// path (plan U2/KTD-2). At/above this Stockfish "Skill Level" (0-20 range),
    /// `humanLikeMove` is never consulted -- callers use `playMove` unchanged. Picked
    /// as the midpoint-ish of the "beatable" half of the range: high enough that
    /// several skill values get some sampled variety, low enough that mid/high skill
    /// settings (where players expect a consistently strong opponent) are untouched.
    public static let lowSkillThreshold = 10

    /// Number of top candidate lines requested for weighted sampling (MultiPV). Small
    /// enough to stay a cheap query, large enough to give genuinely different
    /// reasonable alternatives at most positions.
    public static let humanLikeMultiPV = 4

    /// Pick an OPPONENT reply via weighted random sampling over the engine's own top
    /// `multipv` candidate moves, for skills below `lowSkillThreshold` only (plan
    /// U2/KTD-2). Always a real engine-approved candidate at the requested depth --
    /// never a made-up move -- just not always rank #1.
    ///
    /// Deliberately reuses `analyse` (its cache included) rather than issuing a
    /// separate `runQuery`, and deliberately never touches Stockfish's own "Skill
    /// Level" option -- both per KTD-2: every candidate here must be exactly what
    /// `analyse` would report for this position, with the *sampling* as the sole
    /// source of human-like imperfection. An earlier version ran its own
    /// independent `go` search; the engine here runs multi-threaded (`ensureStarted`
    /// sets Threads > 1), so two separate searches at the same fixed depth are not
    /// guaranteed bit-identical at the margins -- the trailing MultiPV slot could
    /// shuffle between runs, which `EnginePoolHumanLikeSamplingTests` caught as a
    /// sampled move falling outside a ground-truth `analyse` call's candidate set.
    /// Going through `analyse` guarantees the same cached result every time.
    /// Returns nil if there is no legal move (game over).
    public func humanLikeMove(fen: String, depth: Int = 12, skill: Int, multipv: Int = EnginePool.humanLikeMultiPV) async throws -> String? {
        let clampedSkill = max(0, min(20, skill))
        let result = try await analyse(fen: fen, depth: depth, multipv: max(1, multipv))
        return Self.weightedPick(from: result.lines, skill: clampedSkill)
    }

    /// Weighted random pick of a first move (UCI) among candidate lines, favoring
    /// earlier (better-ranked) lines more strongly as `skill` approaches
    /// `lowSkillThreshold` -- lower skill means flatter, closer-to-random weighting;
    /// skill just below the threshold means the top candidate dominates, so behavior
    /// approaches (but, by construction of the caller's threshold check, never
    /// reaches) `playMove`'s always-best behavior. Exposed for direct unit testing of
    /// the sampling curve without spinning up the engine. Never crashes: gracefully
    /// handles fewer than `multipv` candidates (including exactly one), and falls
    /// back to the top candidate for any degenerate input (empty lines, all-empty
    /// PVs, or an out-of-band skill).
    static func weightedPick(
        from lines: [EngineLineResult],
        skill: Int,
        lowSkillThreshold: Int = EnginePool.lowSkillThreshold
    ) -> String? {
        let candidates = lines.compactMap { $0.pvUCI.first }
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }

        // decay in (0, 1]: how much each successive rank's weight shrinks relative to
        // the previous one. Close to 1 => nearly flat/random; close to 0 => sharply
        // favors rank 0. `t` sweeps 0...1 across the low-skill band.
        let band = max(1, lowSkillThreshold - 1)
        let t = Double(max(0, min(lowSkillThreshold - 1, skill))) / Double(band)
        let flattestDecay = 0.85   // skill == 0: most human-like/random
        let sharpestDecay = 0.20   // skill == lowSkillThreshold - 1: strongly favors best
        let decay = flattestDecay + (sharpestDecay - flattestDecay) * t

        var weights = [Double](repeating: 0, count: candidates.count)
        var total = 0.0
        for i in 0..<candidates.count {
            let w = pow(decay, Double(i))
            weights[i] = w
            total += w
        }
        guard total > 0 else { return candidates[0] }

        let r = Double.random(in: 0..<total)
        var running = 0.0
        for i in 0..<candidates.count {
            running += weights[i]
            if r < running { return candidates[i] }
        }
        return candidates[candidates.count - 1]
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

    /// Send `position` + `go depth`, collect the resulting multipv info lines. Caller
    /// must already hold the busy gate and have called `ensureStarted()`; shared by
    /// `analyse` and `humanLikeMove` so both go through the identical MultiPV
    /// request/response plumbing.
    private func runQuery(fen: String, depth: Int, multipv: Int) async throws -> AnalysisResult {
        if multipv != currentMultipv {
            await engine.send(command: .setoption(id: "MultiPV", value: "\(multipv)"))
            currentMultipv = multipv
        }
        currentInfos = [:]
        await engine.send(command: .position(.fen(fen)))

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.waiter = cont
            Task { await engine.send(command: .go(depth: depth)) }
        }

        var lines: [EngineLineResult] = []
        for idx in 1...multipv {
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
        return AnalysisResult(fen: fen, depth: depth, lines: lines)
    }

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
