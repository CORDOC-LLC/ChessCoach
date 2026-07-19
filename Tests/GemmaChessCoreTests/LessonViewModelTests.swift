//  LessonViewModelTests.swift
//  Drives a lesson's practice session against a fixture pack (no real
//  network access -- `startSession(pack:)` skips the download): the
//  configured slice is ordered easiest-first, a wrong answer allows an
//  ordinary retry (not Puzzle Rush's penalty/end-of-run behavior), solving
//  the whole sequence marks the lesson complete in `LessonProgressStore`,
//  and a too-large `puzzleCount` degrades gracefully to however many
//  puzzles the pack actually has.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("LessonViewModel")
struct LessonViewModelTests {

    // Real 2-ply mate-in-1 puzzles (same fixture shape as PuzzleViewModelTests/
    // PuzzleRushSessionTests): the setup move auto-plays, then the solver has
    // one move to find.
    private let easy = Puzzle(
        id: "00lhe",
        fen: "r2q1b1k/ppp3Bp/3pPp2/2n1n3/4P2P/1B3P2/PPP3Q1/2K3RR b - - 0 23",
        moves: ["f8g7", "g2g7"],
        rating: 399,
        themes: ["mateIn1"]
    )
    private let hard = Puzzle(
        id: "harder",
        fen: "r2q1b1k/ppp3Bp/3pPp2/2n1n3/4P2P/1B3P2/PPP3Q1/2K3RR b - - 0 23",
        moves: ["f8g7", "g2g7"],
        rating: 1800,
        themes: ["mateIn1"]
    )

    private func lesson(puzzleCount: Int = 2) -> Lesson {
        Lesson(id: "test-lesson", title: "Test", theme: "mateIn1", bodyText: "Test body.", puzzleCount: puzzleCount)
    }

    @Test("the practice slice is ordered easiest-first, regardless of pack order")
    func practiceSliceIsEasiestFirst() {
        let vm = LessonViewModel(lesson: lesson(), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [hard, easy]))

        #expect(vm.puzzles.map(\.id) == [easy.id, hard.id])
        #expect(vm.currentPuzzle?.id == easy.id)
    }

    @Test("the practice slice is capped at the lesson's configured puzzleCount")
    func practiceSliceCapsAtConfiguredCount() {
        let vm = LessonViewModel(lesson: lesson(puzzleCount: 1), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [easy, hard]))

        #expect(vm.totalCount == 1)
        #expect(vm.puzzles.map(\.id) == [easy.id])
    }

    @Test("a puzzleCount larger than the pack degrades gracefully to however many puzzles exist")
    func practiceSliceDegradesGracefullyWhenPackIsSmaller() {
        let vm = LessonViewModel(lesson: lesson(puzzleCount: 15), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [easy]))

        #expect(vm.totalCount == 1)
    }

    @Test("a wrong-but-legal move is rejected and allows an ordinary retry, not a Rush-style penalty")
    func wrongAnswerAllowsRetry() throws {
        let vm = LessonViewModel(lesson: lesson(), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [easy, hard]))
        let fenBefore = vm.fen

        let dests = ChessLogic.legalDestinations(forFEN: vm.fen)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        let move = try #require(wrong)
        vm.tap(move.from)
        vm.tap(move.to)

        #expect(vm.feedback == .incorrect)
        #expect(vm.fen == fenBefore)   // rejected, not applied
        #expect(vm.currentPuzzle?.id == easy.id)   // still the same puzzle -- an ordinary retry

        // Retrying with the correct move still solves it.
        vm.tap(g2)
        vm.tap(g7)
        #expect(vm.feedback == .solved)
    }

    @Test("solving every puzzle in the sequence marks the lesson complete in LessonProgressStore")
    func solvingWholeSequenceMarksLessonComplete() throws {
        let defaults = UserDefaults(suiteName: #function)!
        let vm = LessonViewModel(lesson: lesson(puzzleCount: 2), progressDefaults: defaults)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [easy, hard]))

        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))

        // First puzzle.
        vm.tap(g2); vm.tap(g7)
        #expect(vm.feedback == .solved)
        #expect(vm.solvedCount == 1)
        #expect(vm.isLessonComplete == false)
        #expect(LessonProgressStore.progress(for: "test-lesson", defaults: defaults) == .inProgress(solvedCount: 1))

        vm.nextPuzzle()
        #expect(vm.currentPuzzle?.id == hard.id)

        // Second (last) puzzle.
        vm.tap(g2); vm.tap(g7)
        #expect(vm.feedback == .solved)
        #expect(vm.solvedCount == 2)
        #expect(vm.isLessonComplete)
        #expect(LessonProgressStore.progress(for: "test-lesson", defaults: defaults) == .completed)
    }

    @Test("selecting a piece to retry clears a lingering 'Not quite' message")
    func selectingNewPieceClearsIncorrectFeedback() throws {
        let vm = LessonViewModel(lesson: lesson(), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [easy, hard]))

        let dests = ChessLogic.legalDestinations(forFEN: vm.fen)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        let move = try #require(wrong)
        vm.tap(move.from); vm.tap(move.to)
        #expect(vm.feedback == .incorrect)
        #expect(vm.status == "Not quite — try again.")

        // Picking up a piece to retry clears the stale error state instead of
        // leaving it displayed while a fresh attempt is underway.
        vm.tap(g2)
        #expect(vm.feedback == nil)
        #expect(vm.status == "Find the best move.")
        #expect(vm.selected == g2)
    }

    @Test("a tap during the mid-transition 'Correct!' window (before the auto-reply plays) is ignored")
    func tapDuringCorrectTransitionIsIgnored() throws {
        // A 4-ply puzzle so there's a real auto-reply gap after the solver's
        // first correct move (the 2-ply fixtures above finish immediately on
        // the only solving move, so they never reach the `.correct`
        // transitional state at all).
        let longPuzzle = Puzzle(
            id: "long",
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moves: ["e2e4", "e7e5", "g1f3", "b8c6"],
            rating: 500,
            themes: ["mateIn1"]
        )
        let vm = LessonViewModel(lesson: lesson(puzzleCount: 1), progressDefaults: UserDefaults(suiteName: #function)!)
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [longPuzzle]))
        #expect(vm.solverIsWhite == false)   // White's e4 auto-played; Black solves

        let e7 = try #require(BoardGeometry.square("e7"))
        let e5 = try #require(BoardGeometry.square("e5"))
        vm.tap(e7); vm.tap(e5)
        #expect(vm.feedback == .correct)
        let fenDuringTransition = vm.fen
        let selectedDuringTransition = vm.selected

        // The scheduled auto-reply Task hasn't run yet (no suspension point
        // has occurred) -- a tap right now must be fully ignored, not treated
        // as a new selection.
        let g8 = try #require(BoardGeometry.square("g8"))
        vm.tap(g8)
        #expect(vm.selected == selectedDuringTransition)
        #expect(vm.fen == fenDuringTransition)
    }

    @Test("a pack-download failure surfaces loadError distinctly from an in-session miss")
    func downloadFailureSurfacesLoadError() async {
        // A theme with no real remote pack (or offline) -- `start()` goes
        // through the real network path and fails; `loadError` must be set,
        // not a crash, and the session must remain empty.
        let vm = LessonViewModel(
            lesson: Lesson(id: "bad", title: "Bad", theme: "not-a-real-theme-xyz", bodyText: "x"),
            progressDefaults: UserDefaults(suiteName: #function)!,
            puzzleBaseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await vm.start()

        #expect(vm.loadError != nil)
        #expect(vm.puzzles.isEmpty)
        #expect(vm.isLoadingPack == false)
    }
}
