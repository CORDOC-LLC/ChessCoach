//  PlayHistoryBridgeTests.swift
//  Covers PlayViewModel.finalizeOutcome()'s HistoryStore bridging -- a finished
//  Play game feeds HistoryStore exactly once, when the player LEAVES the game
//  (plan U3's deferred recording), and reopening an already-finished game for
//  replay never re-appends it.

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
@Suite("Play: HistoryStore bridge", .serialized)
struct PlayHistoryBridgeTests {

    @Test("resigning immediately (under the 10-ply floor) records no HistoryStore entry")
    func shortResignedGameIsNotRecorded() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.resign()
        vm.finalizeOutcome()   // recording is deferred to game exit now (plan U3)

        let history = HistoryStore(baseDir: vm.historyBaseDir)
        #expect(history.loadRecords().isEmpty)
    }

    /// A 12-ply unfinished game, long enough to clear
    /// `HistoryStore.minPlyCountForHistory`. All plies are placeholder `a2a3`
    /// against the standard start FEN -- `buildGameRecord` only needs the ply
    /// count and the parallel arrays to line up, and loading it leaves White
    /// (the user) to move, so no engine task is spawned.
    private func longUnfinishedGame() -> SavedGame {
        let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        return SavedGame(
            id: UUID(), startedAt: Date(), updatedAt: Date(), playerIsWhite: true,
            startFEN: startFEN,
            moves: Array(repeating: "a2a3", count: 12),
            sanMoves: Array(repeating: "a3", count: 12),
            fenHistory: Array(repeating: startFEN, count: 13),
            skill: 6, isGameOver: false, resultText: nil, openingName: nil, openingECO: nil,
            moveNotes: [:], gameSummary: nil, moveRecords: [])
    }

    @Test("a finished game appends no history record until finalize, then exactly one (R7/R9)")
    func historyRecordIsAppendedOnceAtFinalize() {
        let vm = PlayViewModel.forTesting()
        vm.load(longUnfinishedGame())
        let history = HistoryStore(baseDir: vm.historyBaseDir)

        vm.resign()
        #expect(vm.pendingOutcome == .loss)
        #expect(history.loadRecords().isEmpty)   // deferred: nothing written at game over

        vm.finalizeOutcome()
        #expect(history.loadRecords().count == 1)

        // R9: repeat exits don't re-append.
        vm.finalizeOutcome()
        vm.finalizeOutcome()
        #expect(history.loadRecords().count == 1)
    }

    @Test("undoing the game-ending move leaves no history record (R8)")
    func undoLeavesNoHistoryRecord() {
        let vm = PlayViewModel.forTesting()
        vm.load(longUnfinishedGame())
        let history = HistoryStore(baseDir: vm.historyBaseDir)

        vm.resign()
        vm.undoLastMove()
        #expect(vm.pendingOutcome == nil)

        vm.finalizeOutcome()
        #expect(history.loadRecords().isEmpty)
        #expect(!vm.showReviewPrompt)
    }

    @Test("loading a previously-finished game sets no pending outcome, so finalize records nothing")
    func loadingFinishedGameSetsNoPendingOutcome() {
        let vm = PlayViewModel.forTesting()
        var finished = longUnfinishedGame()
        finished = SavedGame(
            id: finished.id, startedAt: finished.startedAt, updatedAt: finished.updatedAt,
            playerIsWhite: true, startFEN: finished.startFEN, moves: finished.moves,
            sanMoves: finished.sanMoves, fenHistory: finished.fenHistory, skill: finished.skill,
            isGameOver: true, resultText: "Checkmate — you win! 🎉", openingName: nil,
            openingECO: nil, moveNotes: [:], gameSummary: nil, moveRecords: [])

        let statsBefore = vm.stats
        vm.load(finished)
        #expect(vm.gameOver)
        #expect(vm.pendingOutcome == nil)

        vm.finalizeOutcome()
        #expect(HistoryStore(baseDir: vm.historyBaseDir).loadRecords().isEmpty)
        #expect(vm.stats == statsBefore)
    }

    @Test("loading an already-finished game for replay does not append a second HistoryStore record")
    func replayingAFinishedGameDoesNotDoubleRecord() async {
        let token = UUID().uuidString
        let savedGamesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayHistoryBridgeTests-saved-\(token)", isDirectory: true)
        let historyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayHistoryBridgeTests-history-\(token)", isDirectory: true)
        let savedGamesDefaults = UserDefaults(suiteName: "PlayHistoryBridgeTests-\(token)")!

        func makeVM() -> PlayViewModel {
            PlayViewModel(
                savedGamesBaseDir: savedGamesDir, savedGamesDefaults: savedGamesDefaults,
                statsDefaults: UserDefaults(suiteName: "PlayHistoryBridgeTestsStats-\(token)")!,
                historyBaseDir: historyDir)
        }

        let vm = makeVM()
        vm.newGame(asWhite: true)
        vm.resign()
        vm.finalizeOutcome()   // recording is deferred to game exit now (plan U3)
        await vm.flushPendingSave()   // checkpoint writes are async now
        let saved = SavedGameStore.load(id: vm.gameID, baseDir: savedGamesDir)

        let history = HistoryStore(baseDir: historyDir)
        let countBeforeReplay = history.loadRecords().count

        // Same saved-games/history dirs as `vm` -- this is what actually exercises
        // "does load() append to the same store", unlike two independent
        // `forTesting()` calls (which would each get their own scratch dir).
        let replay = makeVM()
        replay.load(try! #require(saved))

        // `load(_:)` never records -- confirms no new record appears,
        // regardless of what `countBeforeReplay` was (0, since this game is under the
        // 10-ply floor, but the assertion holds for any starting count).
        #expect(history.loadRecords().count == countBeforeReplay)
    }
}
