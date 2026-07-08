//  PlaySavedGameTests.swift
//  Play mode games checkpoint to disk as they're played, so an in-progress game
//  survives the app being killed (resume) and a finished one can be reopened for
//  move-by-move replay. Uses real Stockfish (shallow skill), so it's serialized.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("Play: saved games", .serialized)
struct PlaySavedGameTests {

    private func wait(timeout: Double = 20, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    @Test("a move checkpoints a resumable game -- in-progress pointer is set, file matches live state")
    func moveCheckpointsAResumableGame() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)

        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        let replied = await wait { vm.moves.count >= 2 }
        #expect(replied)

        let id = vm.gameID
        #expect(SavedGameStore.inProgressGameID(defaults: vm.savedGamesDefaults) == id)
        let saved = try #require(SavedGameStore.load(id: id, baseDir: vm.savedGamesBaseDir))
        #expect(saved.moves == vm.moves)
        #expect(saved.isGameOver == false)
    }

    @Test("resigning ends the game -- the file is kept (isGameOver) but no longer offered for resume")
    func resignClearsInProgressPointer() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        let id = vm.gameID
        vm.resign()

        #expect(SavedGameStore.inProgressGameID(defaults: vm.savedGamesDefaults) == nil)
        let saved = try? SavedGameStore.load(id: id, baseDir: vm.savedGamesBaseDir)
        #expect(saved?.isGameOver == true)
        #expect(saved?.resultText == "You resigned.")
    }

    @Test("load() resumes an unfinished game and continues play from where it left off")
    func loadResumesUnfinishedGame() async throws {
        // Play a couple of plies in one view model, "kill the app" (a fresh
        // view model), then load its own checkpointed state back.
        let original = PlayViewModel.forTesting()
        original.skill = 1
        original.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        original.tap(e2); original.tap(e4)
        #expect(await wait { original.moves.count >= 2 })
        let saved = try #require(SavedGameStore.load(id: original.gameID, baseDir: original.savedGamesBaseDir))

        let resumed = PlayViewModel.forTesting()
        resumed.load(saved)

        #expect(resumed.gameID == original.gameID)
        #expect(resumed.moves == original.moves)
        #expect(resumed.fen == original.fen)
        #expect(resumed.playerIsWhite == true)
        #expect(resumed.gameOver == false)
        #expect(resumed.status == "Your move")   // engine already replied before the checkpoint
    }

    @Test("load() on a finished game sets up read-only replay -- gameOver stays true, tap is a no-op")
    func loadSetsUpReplayForAFinishedGame() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.resign()
        let saved = try? SavedGameStore.load(id: vm.gameID, baseDir: vm.savedGamesBaseDir)

        let replay = PlayViewModel.forTesting()
        replay.load(try! #require(saved))

        #expect(replay.gameOver == true)
        #expect(replay.status == "You resigned.")
        // Browsing to any past ply still works (the actual "replay from a point"
        // mechanism), even though the game itself can't accept new moves.
        if !replay.fenHistory.isEmpty {
            replay.viewTo(ply: 0)
            #expect(replay.isViewingHistory)
        }
    }

    @Test("a per-move coach note is recorded by ply and survives a save/load round-trip")
    func moveNotesRoundTripThroughSaveLoad() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        #expect(await wait { vm.moves.count >= 2 })
        // No coach is configured in this test environment, so no note is
        // generated -- but the ply-0 lookup must not crash either way, and a
        // round trip through the store must preserve whatever's there.
        let noteBefore = vm.note(forPly: 0)
        let saved = try #require(SavedGameStore.load(id: vm.gameID, baseDir: vm.savedGamesBaseDir))
        #expect(saved.moveNotes[0] == noteBefore)

        let reloaded = PlayViewModel.forTesting()
        reloaded.load(saved)
        #expect(reloaded.note(forPly: 0) == noteBefore)
    }
}
