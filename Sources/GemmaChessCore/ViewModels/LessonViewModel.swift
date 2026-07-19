//  LessonViewModel.swift
//  Drives one lesson's practice session: resolves the lesson's configured
//  puzzle count from its matching theme pack (downloading it on demand via
//  `PuzzleDownloadStore`, same as normal Puzzles mode), then solves them one
//  at a time. Move validation and the tap-to-move state machine mirror
//  `PuzzleViewModel`'s approach exactly (a plain string compare against the
//  puzzle's own solution, no engine call) -- a wrong answer here allows an
//  ordinary retry, unlike Puzzle Rush's timed penalty/end-of-run behavior,
//  since a curated lesson isn't timed. Entirely free -- no coach, no
//  `ProEntitlementStore` gate anywhere in this file.

import SwiftUI
import ChessKit

@MainActor
@Observable
public final class LessonViewModel {

    public let lesson: Lesson

    // MARK: Practice session
    public private(set) var puzzles: [Puzzle] = []
    public private(set) var puzzleIndex = 0
    public var fen: String = ""
    public var lastMove: (from: Square, to: Square)?
    public var selected: Square?
    public var status: String = ""
    public var feedback: PuzzleFeedback?
    public var solverIsWhite = true
    public private(set) var solvedCount = 0
    public private(set) var isLessonComplete = false

    // MARK: Loading the theme pack
    public private(set) var isLoadingPack = false
    public private(set) var loadError: String?

    private var dests: [Square: [Square]] = [:]
    private var moveCursor = 0
    private var sessionGen = 0
    /// Injectable so tests use scratch storage instead of the real
    /// Application Support directory / `UserDefaults.standard`.
    private let progressDefaults: UserDefaults
    private let puzzleBaseDir: URL

    public init(
        lesson: Lesson,
        progressDefaults: UserDefaults = .standard,
        puzzleBaseDir: URL = PuzzleDownloadStore.defaultBaseDir
    ) {
        self.lesson = lesson
        self.progressDefaults = progressDefaults
        self.puzzleBaseDir = puzzleBaseDir
    }

    // MARK: Derived

    public var currentPuzzle: Puzzle? {
        puzzles.indices.contains(puzzleIndex) ? puzzles[puzzleIndex] : nil
    }
    public var orientation: BoardOrientation { solverIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }
    public var totalCount: Int { puzzles.count }
    public var isSessionComplete: Bool { !puzzles.isEmpty && currentPuzzle == nil }

    // MARK: Starting the lesson

    /// Downloads (or loads the cached copy of) the lesson's theme pack and
    /// starts the practice session. `loadError` surfaces a download failure
    /// (e.g. offline) distinctly from a normal in-session puzzle miss.
    public func start() async {
        isLoadingPack = true
        loadError = nil
        defer { isLoadingPack = false }
        do {
            let pack = try await PuzzleDownloadStore.downloadPack(theme: lesson.theme, baseDir: puzzleBaseDir)
            startSession(pack: pack)
        } catch {
            loadError = (error as? PuzzleError)?.message ?? error.localizedDescription
        }
    }

    /// Starts a session directly from an already-loaded pack, skipping the
    /// download -- a seam for tests to drive a session without real network
    /// access.
    func startSession(pack: PuzzlePack) {
        sessionGen += 1
        puzzles = Self.orderedPractice(from: pack.puzzles, count: lesson.puzzleCount)
        puzzleIndex = 0
        solvedCount = 0
        isLessonComplete = false
        loadCurrentPuzzle()
    }

    /// The lesson's practice slice: `count` puzzles from `puzzles`, easiest
    /// first (or fewer, if the pack itself has fewer than `count`).
    static func orderedPractice(from puzzles: [Puzzle], count: Int) -> [Puzzle] {
        Array(puzzles.sorted { $0.rating < $1.rating }.prefix(count))
    }

    /// Advances to the next practice puzzle (or ends the session once the
    /// last one is solved).
    public func nextPuzzle() {
        guard puzzleIndex + 1 < puzzles.count else {
            puzzleIndex += 1   // -> currentPuzzle == nil -> isSessionComplete
            return
        }
        sessionGen += 1
        puzzleIndex += 1
        loadCurrentPuzzle()
    }

    private func loadCurrentPuzzle() {
        guard let puzzle = currentPuzzle else { return }
        fen = puzzle.fen
        moveCursor = 0
        selected = nil
        lastMove = nil
        feedback = nil
        applyAutoMove()   // the setup move -- reveals the actual puzzle position
        solverIsWhite = ChessLogic.sideToMove(forFEN: fen) == .white
        refreshDests()
        status = "Find the best move."
    }

    // MARK: Tap-to-move

    public func tap(_ square: Square) {
        // `.solved` (puzzle finished) and `.correct` (mid-way through the
        // opponent's auto-reply delay in attemptMove) both disable tapping --
        // `dests` briefly reflects the opponent's side to move during that
        // window, so a tap on the user's own piece would otherwise silently
        // do nothing and read as "the board isn't responding."
        guard currentPuzzle != nil, feedback != .solved, feedback != .correct else { return }
        if let sel = selected, let d = dests[sel], d.contains(square) {
            attemptMove(from: sel, to: square)
            return
        }
        let newSelection = (dests[square] != nil) ? square : nil
        selected = newSelection
        // Picking up a piece to retry clears a lingering "Not quite" from the
        // previous miss, instead of leaving stale error feedback on screen
        // while the user is mid-way through a fresh attempt.
        if newSelection != nil, feedback == .incorrect {
            feedback = nil
            status = "Find the best move."
        }
    }

    private func attemptMove(from: Square, to: Square) {
        guard let puzzle = currentPuzzle, moveCursor < puzzle.moves.count else { return }
        let fromFEN = fen
        let attempted = uci(from: from, to: to, in: fromFEN)
        selected = nil
        let expected = puzzle.moves[moveCursor]
        guard attempted == expected else {
            feedback = .incorrect
            status = "Not quite — try again."
            return
        }
        guard let next = ChessLogic.fen(afterMove: attempted, fromFEN: fromFEN) else { return }
        fen = next
        lastMove = (from, to)
        moveCursor += 1
        refreshDests()

        if moveCursor >= puzzle.moves.count {
            finishPuzzle()
            return
        }
        feedback = .correct
        status = "Correct!"
        let gen = sessionGen
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard gen == self.sessionGen else { return }
            self.applyAutoMove()
            self.refreshDests()
            if self.moveCursor >= puzzle.moves.count {
                self.finishPuzzle()
            } else {
                self.feedback = nil
                self.status = "Find the best move."
            }
        }
    }

    private func finishPuzzle() {
        solvedCount += 1
        feedback = .solved
        status = "Solved!"
        let complete = solvedCount >= puzzles.count
        isLessonComplete = complete
        LessonProgressStore.recordAttempt(
            lessonID: lesson.id, solvedCount: solvedCount, isComplete: complete, defaults: progressDefaults
        )
    }

    // MARK: Helpers (mirror PuzzleViewModel's private helpers)

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
