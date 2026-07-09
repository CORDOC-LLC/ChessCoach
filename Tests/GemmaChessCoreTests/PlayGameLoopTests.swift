//  PlayGameLoopTests.swift
//  Integration test for the live Play loop: a user move via tap-to-move drives a
//  real engine reply plus the engine-grounded verdict, and game state stays
//  consistent. Uses real Stockfish (shallow skill), so it's serialized.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("Play: game loop", .serialized)
struct PlayGameLoopTests {

    /// Poll `condition` on the MainActor until true or timeout (engine reply is async).
    private func wait(timeout: Double = 40, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }
        return condition()
    }

    @Test("a tapped user move triggers a legal engine reply and updates state")
    func userMoveThenEngineReply() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1                 // weak + fast opponent
        vm.newGame(asWhite: true)

        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2)                   // select
        #expect(vm.selected == e2)
        vm.tap(e4)                   // move 1. e4

        // User move applied immediately.
        #expect(vm.moves.first == "e2e4")
        #expect(vm.sanMoves.first == "e4")
        #expect(vm.selected == nil)

        // Engine replies asynchronously.
        let replied = await wait { vm.moves.count >= 2 }
        #expect(replied)
        #expect(!vm.gameOver)
        #expect(vm.fenHistory.count == vm.moves.count + 1)   // start + one per ply
        #expect(vm.sanMoves.count == vm.moves.count)
        // Engine's reply is a legal black move (parses to two valid squares).
        let reply = vm.moves[1]
        #expect(BoardGeometry.square(String(reply.prefix(2))) != nil)
        #expect(BoardGeometry.square(String(reply.dropFirst(2).prefix(2))) != nil)

        // The engine-grounded verdict on the user's move is set (independent of the
        // language coach, which may be unavailable on the test host).
        let graded = await wait { vm.lastVerdict != nil }
        #expect(graded)
        #expect(vm.lastVerdict?.moveSAN == "e4")
        // The Best Moves top-3 list is engine-only too -- populated regardless
        // of coach availability, capped at 3, best line first.
        #expect(!vm.topMoves.isEmpty)
        #expect(vm.topMoves.count <= 3)
        #expect(vm.topMoves.allSatisfy { $0.lineSAN.first != nil })
        // After the dust settles it's the user's move again with a fresh eval.
        let settled = await wait { !vm.engineThinking }
        #expect(settled)
        #expect(vm.status == "Your move")
    }

    @Test("tapping is ignored while browsing history; returnToLive restores play")
    func viewingDisablesTap() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        _ = await wait { vm.moves.count >= 2 }

        vm.viewTo(ply: 0)                      // browse the start position
        #expect(vm.isViewingHistory)
        #expect(vm.displayFEN == PlayViewModel.startFEN)
        let liveMoves = vm.moves.count
        let d2 = try #require(BoardGeometry.square("d2"))
        vm.tap(d2)                              // ignored while viewing
        #expect(vm.selected == nil)
        #expect(vm.moves.count == liveMoves)

        vm.returnToLive()
        #expect(!vm.isViewingHistory)
        #expect(vm.displayFEN == vm.fen)
    }

    @Test("undo rewinds the user's move and the engine's reply, regardless of grade")
    func undoRewindsLastRound() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        _ = await wait { vm.lastVerdict != nil && vm.moves.count >= 2 && !vm.engineThinking }

        // Undo has no classification gate -- available for best moves too, since
        // this is about learning, not defending a good score.
        #expect(vm.canUndo)

        vm.undoLastMove()
        // Both plies gone; back to the start, user to move, nothing graded.
        #expect(vm.moves.isEmpty)
        #expect(vm.sanMoves.isEmpty)
        #expect(vm.fen == PlayViewModel.startFEN)
        #expect(vm.fenHistory == [PlayViewModel.startFEN])
        #expect(vm.lastVerdict == nil)
        #expect(vm.topMoves.isEmpty)
        #expect(vm.lastCoachNote == nil)
        #expect(vm.moveRecords.isEmpty)
        #expect(!vm.gameOver)
        #expect(!vm.canUndo)           // nothing left to undo
        #expect(vm.userToMove)

        // The board is fully playable again.
        vm.tap(e2)
        #expect(vm.selected == e2)
    }

    @Test("undo is repeatable -- multiple rounds can be taken back in a row")
    func undoIsRepeatable() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        let d2 = try #require(BoardGeometry.square("d2"))
        let d4 = try #require(BoardGeometry.square("d4"))

        vm.tap(e2); vm.tap(e4)
        _ = await wait { vm.moves.count >= 2 && !vm.engineThinking }
        vm.tap(d2); vm.tap(d4)
        _ = await wait { vm.moves.count >= 4 && !vm.engineThinking }
        #expect(vm.moveRecords.count == 2)

        vm.undoLastMove()
        #expect(vm.moves.count == 2)
        #expect(vm.moveRecords.count == 1)
        #expect(vm.canUndo)             // one more round left to take back

        vm.undoLastMove()
        #expect(vm.moves.isEmpty)
        #expect(vm.moveRecords.isEmpty)
        #expect(!vm.canUndo)            // back to the very start
    }

    @Test("graded user moves accumulate into the summary records")
    func moveRecordsAccumulate() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        _ = await wait { vm.lastVerdict != nil }
        #expect(vm.moveRecords.count == 1)
        #expect(vm.moveRecords.first?.san == "e4")
        #expect(vm.moveRecords.first?.moveNumber == 1)
        // The record carries real win% inputs for the accuracy math.
        let r = try #require(vm.moveRecords.first)
        #expect(r.winBefore >= 0 && r.winBefore <= 100)
    }

    @Test("the opening is named live after book moves")
    func openingNamedLive() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)                 // 1. e4 is a named book position
        let named = await wait { vm.opening != nil }
        #expect(named)
        #expect(vm.opening?.name.isEmpty == false)
        vm.newGame(asWhite: true)
        #expect(vm.opening == nil)             // reset with the game
    }
}
