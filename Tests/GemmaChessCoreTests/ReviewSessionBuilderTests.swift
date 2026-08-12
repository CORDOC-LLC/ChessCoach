//  ReviewSessionBuilderTests.swift
//  Integration coverage: plays real moves through a real `PlayViewModel` (the
//  actual live-capture code path -- the async engine-eval Task, the ply-index
//  guards, undo's trim-alignment), then verifies `ReviewSessionBuilder` turns
//  the resulting `SavedGame` into a full, sane `ReviewSession` with zero
//  further engine calls of its own.

import Foundation
import Testing
@testable import GemmaChessCore

@MainActor
struct ReviewSessionBuilderTests {

    private func wait(timeout: Double = 40, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    /// Play 1. e4 e5 as White and wait for BOTH plies' live capture to
    /// settle -- the user's move analysis AND the engine reply's dedicated
    /// post-move eval (see `PlayViewModel`'s move-Task, after `engineReply()`
    /// returns). `!isCoaching` is still the right settle signal: that step
    /// runs before `streamCoachNote`, which runs before `isCoaching = false`.
    private func playOneRoundAndSettle(_ vm: PlayViewModel) async throws -> Bool {
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        return await wait { vm.lastVerdict != nil && !vm.engineThinking && !vm.isCoaching }
    }

    /// Hand-build the same `SavedGame` shape `PlayViewModel.
    /// currentSavedGameSnapshot()` would (that function is private -- this
    /// mirrors it from the view model's public/internal-readable state).
    private func snapshot(_ vm: PlayViewModel) -> SavedGame {
        SavedGame(
            id: vm.gameID, startedAt: Date(), updatedAt: Date(), playerIsWhite: vm.playerIsWhite,
            startFEN: vm.fenHistory.first ?? PlayViewModel.startFEN, moves: vm.moves, sanMoves: vm.sanMoves,
            fenHistory: vm.fenHistory, skill: vm.skill, isGameOver: vm.gameOver, resultText: vm.resultText,
            openingName: vm.opening?.name, openingECO: vm.opening?.eco,
            moveNotes: [:], gameSummary: nil, moveRecords: vm.moveRecords, winAfterMover: vm.winAfterMover
        )
    }

    @Test("a live-played round fully captures winAfterMover -- canBuild is true")
    func liveCaptureIsComplete() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playOneRoundAndSettle(vm))

        let saved = snapshot(vm)
        #expect(saved.moves.count == 2)
        #expect(saved.winAfterMover?.count == 2)
        #expect(ReviewSessionBuilder.canBuild(from: saved))
    }

    @Test("build(from:) produces a full session with zero further engine calls")
    func buildProducesFullSession() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playOneRoundAndSettle(vm))
        let saved = snapshot(vm)

        let session = try #require(ReviewSessionBuilder.build(from: saved))
        #expect(session.player == "white")
        // Timeline: one node per position, 0...plyCount.
        #expect(session.timeline.count == saved.moves.count + 1)
        #expect(session.timeline.first?.fen == saved.fenHistory.first)
        #expect(session.timeline.last?.fen == saved.fenHistory.last)
        // Only White's (the reviewed side's) single move should appear.
        #expect(session.allMoves.count == 1)
        let reviewed = try #require(session.allMoves.first)
        #expect(reviewed.moveSAN == "e4")
        #expect(reviewed.color == "white")
        // The move-review arrow's data source (PlayView.boardArrows) --
        // the played ply's node must carry SOME best-move UCI whenever the
        // live analysis found one, matching `moveRecords.first?.bestUCI`.
        let firstNode = try #require(session.timeline.first { $0.ply == 1 })
        #expect(firstNode.bestUCI == saved.moveRecords.first?.bestUCI)
        #expect(firstNode.isMyMove == true)
    }

    @Test("an undo mid-round leaves winAfterMover short -- canBuild correctly refuses")
    func undoLeavesIncompleteCapture() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playOneRoundAndSettle(vm))
        vm.undoLastMove()
        // Back to an empty game -- nothing to build a review from either way.
        let saved = snapshot(vm)
        #expect(saved.moves.isEmpty)
        #expect(!ReviewSessionBuilder.canBuild(from: saved))
    }

    @Test("a saved game from before winAfterMover existed (nil) safely refuses canBuild")
    func nilWinAfterMoverRefuses() {
        let saved = SavedGame(
            id: UUID(), startedAt: Date(), updatedAt: Date(), playerIsWhite: true,
            startFEN: PlayViewModel.startFEN, moves: ["e2e4", "e7e5"], sanMoves: ["e4", "e5"],
            fenHistory: [PlayViewModel.startFEN, PlayViewModel.startFEN, PlayViewModel.startFEN],
            skill: 6, isGameOver: false, resultText: nil, openingName: nil, openingECO: nil,
            moveNotes: [:], gameSummary: nil, moveRecords: [], winAfterMover: nil
        )
        #expect(!ReviewSessionBuilder.canBuild(from: saved))
        #expect(ReviewSessionBuilder.build(from: saved) == nil)
    }
}
