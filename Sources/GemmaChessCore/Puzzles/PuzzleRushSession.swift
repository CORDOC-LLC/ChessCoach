//  PuzzleRushSession.swift
//  "Puzzle Rush": a timed session over already-downloaded puzzle packs --
//  solve as many as possible before the clock runs out, ending immediately on
//  the first wrong answer (mirrors Chess.com/Lichess Puzzle Rush). Entirely
//  free and local: no coach, no network, reuses the same puzzle packs
//  `PuzzleViewModel` solves one-at-a-time in normal Puzzles mode.
//
//  This is a standalone session/view-model rather than a `PuzzleViewModel`
//  extension: Rush's rules diverge from normal puzzle mode in ways that don't
//  compose cleanly with it (a wrong move ends the whole run instead of just
//  being rejected with a retry, and the opponent's forced reply auto-plays
//  immediately instead of after a UX pause, since speed is the point). The
//  move-validation shape (tap-to-select, UCI compare, `ChessLogic.fen(
//  afterMove:fromFEN:)`) is copied from `PuzzleViewModel`'s state machine
//  rather than reinvented.

import Foundation
import ChessKit

/// Why a Rush run ended.
public enum PuzzleRushEndReason: Equatable, Sendable {
    /// The solver played a legal-but-wrong move.
    case wrongAnswer
    /// The countdown reached zero.
    case timeExpired
    /// The solver correctly finished every puzzle in the pool (rare, but
    /// possible with a small pool) -- distinct from failing so the UI can
    /// still celebrate it.
    case queueExhausted
}

@MainActor
@Observable
public final class PuzzleRushSession {

    /// Default run length -- 3 minutes, matching Chess.com's "3 Minute" mode
    /// (the shortest/most common Rush variant). Easy to retune; it's a plain
    /// constructor argument with no external dependents.
    public static let defaultDurationSeconds = 180

    public let durationSeconds: Int
    /// Injected so tests control the clock instead of depending on real time
    /// passing -- `tick(at:)` takes an explicit time for the same reason.
    private let now: () -> Date

    // MARK: Run state

    public private(set) var queue: [Puzzle] = []
    public private(set) var index = 0
    public private(set) var correctCount = 0
    public private(set) var isActive = false
    public private(set) var endReason: PuzzleRushEndReason?
    public private(set) var remainingSeconds: Int
    private var deadline: Date?

    // MARK: Board state (mirrors PuzzleViewModel's shape)

    public private(set) var fen = ""
    public private(set) var lastMove: (from: Square, to: Square)?
    public var selected: Square?
    public private(set) var solverIsWhite = true

    private var dests: [Square: [Square]] = [:]
    private var moveCursor = 0

    public init(durationSeconds: Int = PuzzleRushSession.defaultDurationSeconds, now: @escaping () -> Date = Date.init) {
        self.durationSeconds = durationSeconds
        self.now = now
        self.remainingSeconds = durationSeconds
    }

    // MARK: Derived

    public var currentPuzzle: Puzzle? { queue.indices.contains(index) ? queue[index] : nil }
    /// True once `start(puzzles:)` has been called with no puzzles at all --
    /// the "download puzzles first" state, distinct from a run that ended.
    public var isEmpty: Bool { queue.isEmpty }
    public var hasEnded: Bool { endReason != nil }
    public var orientation: BoardOrientation { solverIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }

    /// Puzzles ordered easiest-first -- a reasonable Rush default (per the
    /// plan's open question) since it lets a run build up a streak before
    /// harder puzzles start costing time, mirroring how Rush difficulty
    /// ramps in Chess.com/Lichess.
    public static func order(_ puzzles: [Puzzle]) -> [Puzzle] {
        puzzles.sorted { $0.rating < $1.rating }
    }

    /// Gathers puzzles from every already-downloaded pack on disk, excluding
    /// puzzles already solved (via `PuzzleProgressStore`) so a Rush run
    /// doesn't waste time re-solving puzzles finished outside Rush mode --
    /// unless doing so would leave a theme's pack empty, in which case that
    /// pack's puzzles are all included anyway (recycling beats an empty
    /// pool). Difficulty-ascending across the combined pool.
    public static func loadPuzzlePool(
        baseDir: URL = PuzzleDownloadStore.defaultBaseDir,
        progressDefaults: UserDefaults = .standard
    ) -> [Puzzle] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var all: [Puzzle] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "catalog.json" {
            guard let data = try? Data(contentsOf: file),
                  let pack = try? JSONDecoder().decode(PuzzlePack.self, from: data)
            else { continue }
            let solved = PuzzleProgressStore.solvedIDs(theme: pack.theme, defaults: progressDefaults)
            let fresh = pack.puzzles.filter { !solved.contains($0.id) }
            all.append(contentsOf: fresh.isEmpty ? pack.puzzles : fresh)
        }
        return order(all)
    }

    // MARK: Running a session

    /// Starts (or restarts) a run from scratch -- no state from a previous
    /// run carries over, including a previous run's `endReason`.
    public func start(puzzles: [Puzzle]) {
        queue = Self.order(puzzles)
        index = 0
        correctCount = 0
        endReason = nil
        remainingSeconds = durationSeconds
        selected = nil
        lastMove = nil
        moveCursor = 0
        dests = [:]

        guard !queue.isEmpty else {
            isActive = false
            fen = ""
            deadline = nil
            return
        }
        isActive = true
        deadline = now().addingTimeInterval(TimeInterval(durationSeconds))
        loadCurrentPuzzle()
    }

    /// Advances the countdown against `time` (defaults to the injected
    /// clock) -- call this periodically (e.g. once a second) from a timer
    /// driver. A no-op once the run has already ended.
    public func tick(at time: Date? = nil) {
        guard isActive, let deadline else { return }
        let reference = time ?? now()
        let remaining = deadline.timeIntervalSince(reference)
        remainingSeconds = max(0, Int(remaining.rounded(.up)))
        if remaining <= 0 {
            end(reason: .timeExpired)
        }
    }

    public func tap(_ square: Square) {
        guard isActive, currentPuzzle != nil else { return }
        if let sel = selected, let d = dests[sel], d.contains(square) {
            attemptMove(from: sel, to: square)
            return
        }
        selected = (dests[square] != nil) ? square : nil
    }

    private func attemptMove(from: Square, to: Square) {
        guard let puzzle = currentPuzzle, moveCursor < puzzle.moves.count else { return }
        let fromFEN = fen
        let attempted = uci(from: from, to: to, in: fromFEN)
        selected = nil
        let expected = puzzle.moves[moveCursor]
        guard attempted == expected else {
            end(reason: .wrongAnswer)
            return
        }
        guard let next = ChessLogic.fen(afterMove: attempted, fromFEN: fromFEN) else { return }
        fen = next
        lastMove = (from, to)
        moveCursor += 1
        refreshDests()

        if moveCursor >= puzzle.moves.count {
            advance()
            return
        }
        // The opponent's forced reply auto-plays immediately -- Rush is
        // timed, so (unlike normal Puzzle mode) there's no UX pause here.
        applyAutoMove()
        refreshDests()
        if moveCursor >= puzzle.moves.count {
            advance()
        }
    }

    private func advance() {
        correctCount += 1
        index += 1
        guard isActive, currentPuzzle != nil else {
            isActive = false
            if endReason == nil { endReason = .queueExhausted }
            return
        }
        loadCurrentPuzzle()
    }

    private func end(reason: PuzzleRushEndReason) {
        isActive = false
        endReason = reason
    }

    // MARK: Helpers (mirror PuzzleViewModel's private helpers)

    private func loadCurrentPuzzle() {
        guard let puzzle = currentPuzzle else { return }
        fen = puzzle.fen
        moveCursor = 0
        selected = nil
        lastMove = nil
        applyAutoMove()
        solverIsWhite = ChessLogic.sideToMove(forFEN: fen) == .white
        refreshDests()
    }

    private func applyAutoMove() {
        guard let puzzle = currentPuzzle, moveCursor < puzzle.moves.count else { return }
        let move = puzzle.moves[moveCursor]
        guard let next = ChessLogic.fen(afterMove: move, fromFEN: fen) else { return }
        lastMove = squares(fromUCI: move)
        fen = next
        moveCursor += 1
    }

    private func refreshDests() { dests = ChessLogic.legalDestinations(forFEN: fen) }

    private func notation(_ sq: Square) -> String {
        let file = Square.File.allCases[sq.file.number - 1].rawValue
        return "\(file)\(sq.rank.value)"
    }

    /// Build a UCI move, auto-queening a pawn that reaches the last rank.
    private func uci(from: Square, to: Square, in fen: String) -> String {
        let placement = BoardGeometry.placement(fromFEN: fen)
        let idx = (from.rank.value - 1) * 8 + (from.file.number - 1)
        let isPawn = placement[idx].map { $0 == "p" || $0 == "P" } ?? false
        let promo = (isPawn && (to.rank.value == 8 || to.rank.value == 1)) ? "q" : ""
        return notation(from) + notation(to) + promo
    }

    private func squares(fromUCI uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4,
              let from = BoardGeometry.square(String(uci.prefix(2))),
              let to = BoardGeometry.square(String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }
}
