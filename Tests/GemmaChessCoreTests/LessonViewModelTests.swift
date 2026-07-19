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
