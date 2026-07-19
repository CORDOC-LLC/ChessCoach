//  PuzzleRushSession.swift
//  "Puzzle Rush": a timed session over already-downloaded puzzle packs --
//  solve as many as possible before the clock runs out. A wrong move no
//  longer ends the run outright: it costs `wrongAnswerPenaltySeconds` off the
//  clock and restarts the SAME puzzle from its setup position, so one miss
//  doesn't throw away the whole run (unless the penalty itself exhausts the
//  clock, which ends the run via `.timeExpired` exactly as a natural
//  countdown would). Entirely free and local: no coach, no network, reuses
//  the same puzzle packs `PuzzleViewModel` solves one-at-a-time in normal
//  Puzzles mode.
//
//  This is a standalone session/view-model rather than a `PuzzleViewModel`
//  extension: Rush's rules diverge from normal puzzle mode in ways that don't
//  compose cleanly with it (a wrong move costs time instead of just being
//  rejected with an unlimited retry, and the opponent's forced reply
//  auto-plays immediately instead of after a UX pause, since speed is the
//  point). The move-validation shape (tap-to-select, UCI compare,
//  `ChessLogic.fen(afterMove:fromFEN:)`) is copied from `PuzzleViewModel`'s
//  state machine rather than reinvented.

import Foundation
import ChessKit

/// Why a Rush run ended. A wrong answer alone no longer ends a run (see this
/// file's header) -- it only shows up here if the penalty it applies happens
/// to exhaust the clock, in which case the reason is `.timeExpired`, not a
/// distinct "you missed one" reason.
public enum PuzzleRushEndReason: Equatable, Sendable {
    /// The countdown reached zero (including via a wrong-answer penalty).
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

    /// Deducted from the clock on every wrong answer, in exchange for
    /// retrying the same puzzle instead of ending the run.
    public static let wrongAnswerPenaltySeconds: TimeInterval = 10

    public private(set) var queue: [Puzzle] = []
    public private(set) var index = 0
    public private(set) var correctCount = 0
    /// Wrong attempts across the whole run (each already reflected in
    /// `remainingSeconds` via the penalty) -- shown on the result card.
    public private(set) var wrongAttempts = 0
    /// Set for a brief moment right after a wrong answer, so the UI can flash
    /// a "-10s" toast before it's cleared on the next tap/tick. Not persisted
    /// across a restart beyond what `start(puzzles:)` already resets.
    public private(set) var justPenalized = false
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

    /// Puzzles grouped into difficulty-ascending bands (bucketed by 100
    /// rating points), shuffled *within* each band -- keeps the same overall
    /// easy-to-hard ramp Chess.com/Lichess Rush uses, while giving a replay a
    /// genuinely different puzzle order instead of the exact same sequence
    /// every time (same-rating puzzles no longer always land in the same
    /// relative spot). `generator` is injectable so tests get a deterministic
    /// shuffle instead of depending on real randomness.
    public static func order<G: RandomNumberGenerator>(
        _ puzzles: [Puzzle], using generator: inout G
    ) -> [Puzzle] {
        let bandSize = 100
        let bands = Dictionary(grouping: puzzles) { $0.rating / bandSize }
        return bands.keys.sorted().flatMap { bands[$0]!.shuffled(using: &generator) }
    }

    /// Convenience overload using the system RNG -- real variety at runtime;
    /// tests use the generic `order(_:using:)` with a fixed generator instead.
    public static func order(_ puzzles: [Puzzle]) -> [Puzzle] {
        var rng = SystemRandomNumberGenerator()
        return order(puzzles, using: &rng)
    }

    /// Gathers puzzles from every already-downloaded pack on disk, excluding
    /// puzzles already solved (via `PuzzleProgressStore`) so a Rush run
    /// doesn't waste time re-solving puzzles finished outside Rush mode --
    /// unless doing so would leave a theme's pack empty, in which case that
    /// pack's puzzles are all included anyway (recycling beats an empty
    /// pool). Difficulty-ascending across the combined pool, shuffled within
    /// each difficulty band (see `order(_:using:)`) for replay variety.
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
        wrongAttempts = 0
        justPenalized = false
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
        justPenalized = false
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
            registerWrongAttempt()
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

    /// A wrong move costs the clock, not the run: apply the penalty, and
    /// restart the current puzzle from its setup position unless the penalty
    /// itself exhausted the clock (in which case `applyPenalty` already
    /// ended the run via `.timeExpired`).
    private func registerWrongAttempt() {
        wrongAttempts += 1
        justPenalized = true
        applyPenalty(seconds: Self.wrongAnswerPenaltySeconds)
        guard isActive else { return }
        loadCurrentPuzzle()
    }

    /// Pulls the deadline closer by `seconds` and immediately recomputes
    /// `remainingSeconds` against the injected clock (rather than waiting for
    /// the next periodic `tick()`), ending the run via `.timeExpired` if that
    /// alone exhausts the clock.
    private func applyPenalty(seconds: TimeInterval) {
        guard let deadline else { return }
        self.deadline = deadline.addingTimeInterval(-seconds)
        tick()
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
