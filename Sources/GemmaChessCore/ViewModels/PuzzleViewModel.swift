//  PuzzleViewModel.swift
//  Puzzle mode: browse themes (downloading a pack on demand), then solve one
//  puzzle at a time. Entirely free -- no coach, no network once a pack is
//  downloaded; move validation is a plain string compare against the
//  puzzle's own solution, no engine call needed either.

import SwiftUI
import ChessKit

/// Transient feedback on the solver's last attempt.
public enum PuzzleFeedback: Equatable, Sendable {
    case correct
    case incorrect
    case solved
}

@MainActor
@Observable
public final class PuzzleViewModel {

    // MARK: Catalog + download
    public var catalog: PuzzleCatalog?
    public var isLoadingCatalog = false
    public var catalogError: String?
    public var downloadingTheme: String?
    public var downloadError: String?

    // MARK: Session
    public var activeTheme: String?
    public private(set) var puzzles: [Puzzle] = []
    public private(set) var puzzleIndex = 0
    public var fen: String = ""
    public var lastMove: (from: Square, to: Square)?
    public var selected: Square?
    public var status: String = ""
    public var feedback: PuzzleFeedback?
    public var solverIsWhite = true
    public private(set) var sessionSolvedCount = 0
    /// Local Elo-lite puzzle-solving rating (see `PuzzleRatingStore`) --
    /// puzzle-solving skill only, not a claim about overall playing
    /// strength. Kept in sync as attempts are scored.
    public private(set) var rating: Int

    private var dests: [Square: [Square]] = [:]
    private var moveCursor = 0
    private var sessionGen = 0
    /// Whether the current puzzle's attempt has already been scored against
    /// the rating -- a puzzle is scored once (first wrong move, or once
    /// fully solved), so retrying after a miss doesn't double-count.
    private var currentAttemptRated = false
    /// Where solved-puzzle progress is tracked, and where downloaded packs are
    /// cached -- both injectable so tests use scratch storage instead of the
    /// real Application Support directory / UserDefaults.standard.
    private let progressDefaults: UserDefaults
    private let puzzleBaseDir: URL

    public init(
        progressDefaults: UserDefaults = .standard,
        puzzleBaseDir: URL = PuzzleDownloadStore.defaultBaseDir
    ) {
        self.progressDefaults = progressDefaults
        self.puzzleBaseDir = puzzleBaseDir
        self.rating = PuzzleRatingStore.currentRating(defaults: progressDefaults)
    }

    // MARK: Derived

    public var currentPuzzle: Puzzle? {
        puzzles.indices.contains(puzzleIndex) ? puzzles[puzzleIndex] : nil
    }
    public var orientation: BoardOrientation { solverIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }
    public var sessionTotalCount: Int { puzzles.count }
    public var isDownloading: Bool { downloadingTheme != nil }
    public var isSessionComplete: Bool { activeTheme != nil && currentPuzzle == nil }

    public func isDownloaded(_ theme: String) -> Bool {
        PuzzleDownloadStore.isDownloaded(theme: theme, baseDir: puzzleBaseDir)
    }

    // MARK: Catalog

    public func loadCatalog() async {
        if let cached = PuzzleDownloadStore.loadCachedCatalog(baseDir: puzzleBaseDir) { catalog = cached }
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }
        do {
            catalog = try await PuzzleDownloadStore.fetchCatalog(baseDir: puzzleBaseDir)
        } catch {
            if catalog == nil {
                catalogError = (error as? PuzzleError)?.message ?? error.localizedDescription
            }
        }
    }

    // MARK: Starting a theme

    public func downloadAndStart(_ theme: String) async {
        downloadingTheme = theme
        downloadError = nil
        defer { downloadingTheme = nil }
        do {
            let pack = try await PuzzleDownloadStore.downloadPack(theme: theme, baseDir: puzzleBaseDir)
            startSession(pack: pack)
        } catch {
            downloadError = (error as? PuzzleError)?.message ?? error.localizedDescription
        }
    }

    /// Starts a session directly from an already-loaded pack, skipping the
    /// download -- the entry point `downloadAndStart` uses once it has one,
    /// and a seam for tests to drive a session without real network access.
    func startSession(pack: PuzzlePack) {
        sessionGen += 1
        activeTheme = pack.theme
        // Fresh puzzles first, so returning to a theme doesn't replay solved ones.
        let solved = PuzzleProgressStore.solvedIDs(theme: pack.theme, defaults: progressDefaults)
        let unsolved = pack.puzzles.filter { !solved.contains($0.id) }
        let done = pack.puzzles.filter { solved.contains($0.id) }
        puzzles = unsolved + done
        puzzleIndex = 0
        sessionSolvedCount = 0
        loadCurrentPuzzle()
    }

    /// Back to the theme list.
    public func endSession() {
        sessionGen += 1
        activeTheme = nil
        puzzles = []
        puzzleIndex = 0
    }

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
        currentAttemptRated = false
        applyAutoMove()   // the setup move -- reveals the actual puzzle position
        solverIsWhite = ChessLogic.sideToMove(forFEN: fen) == .white
        refreshDests()
        status = "Find the best move."
    }

    // MARK: Tap-to-move

    public func tap(_ square: Square) {
        guard currentPuzzle != nil, feedback != .solved else { return }
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
            feedback = .incorrect
            status = "Not quite — try again."
            scoreAttempt(puzzle: puzzle, correct: false)
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
        if let puzzle = currentPuzzle, let theme = activeTheme {
            PuzzleProgressStore.markSolved(puzzle.id, theme: theme, defaults: progressDefaults)
            sessionSolvedCount += 1
            scoreAttempt(puzzle: puzzle, correct: true)
        }
        feedback = .solved
        status = "Solved!"
    }

    /// Scores this puzzle against the rating exactly once per attempt --
    /// the first wrong move fails it (a retry after a miss doesn't count
    /// again), or a full solve without any miss counts as correct.
    private func scoreAttempt(puzzle: Puzzle, correct: Bool) {
        guard !currentAttemptRated else { return }
        currentAttemptRated = true
        rating = PuzzleRatingStore.update(puzzleRating: puzzle.rating, correct: correct, defaults: progressDefaults)
    }

    // MARK: Helpers

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
