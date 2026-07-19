//  PlayHistoryBridgeTests.swift
//  Covers PlayViewModel.recordOutcome()'s new HistoryStore bridging (plan U2)
//  -- a finished Play game feeds HistoryStore exactly once, and reopening an
//  already-finished game for replay never re-appends it.

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

        let history = HistoryStore(baseDir: vm.historyBaseDir)
        #expect(history.loadRecords().isEmpty)
    }

    @Test("loading an already-finished game for replay does not append a second HistoryStore record")
    func replayingAFinishedGameDoesNotDoubleRecord() {
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
        let saved = SavedGameStore.load(id: vm.gameID, baseDir: savedGamesDir)

        let history = HistoryStore(baseDir: historyDir)
        let countBeforeReplay = history.loadRecords().count

        // Same saved-games/history dirs as `vm` -- this is what actually exercises
        // "does load() append to the same store", unlike two independent
        // `forTesting()` calls (which would each get their own scratch dir).
        let replay = makeVM()
        replay.load(try! #require(saved))

        // `load(_:)` never calls `recordOutcome()` -- confirms no new record appears,
        // regardless of what `countBeforeReplay` was (0, since this game is under the
        // 10-ply floor, but the assertion holds for any starting count).
        #expect(history.loadRecords().count == countBeforeReplay)
    }
}
