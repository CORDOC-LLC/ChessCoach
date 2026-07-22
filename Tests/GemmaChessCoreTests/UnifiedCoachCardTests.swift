//  UnifiedCoachCardTests.swift
//  Plan 2026-07-21-003 U4 — the unified Coach card's view-model wiring: after a
//  graded move both tiers get the verdict AND the free template comment
//  (`lastEngineComment`, origin AE1/AE2); with the Coach toggle off the engine
//  content still populates but no coach note or error appears (AE4); a
//  non-entitled App Store user never fires the per-move Pro prose call at all;
//  and the comment clears wherever the verdict clears. Uses real Stockfish
//  (shallow skill), so it's serialized.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

/// A coach whose STREAMING endpoint answers `text` -- `mockAnswering` returns a
/// plain JSON body, which `ManagedCoach.stream` (SSE, `data:`-prefixed lines)
/// yields nothing from, so the per-move-note tests here need the SSE shape.
private func mockStreaming(_ text: String) -> ManagedCoach {
    .mock { _ in
        (200, Data("data: {\"text\":\"\(text)\"}\n\ndata: [DONE]\n".utf8))
    }
}

@MainActor
@Suite("Play: unified Coach card (U4)", .serialized)
struct UnifiedCoachCardTests {

    /// Poll `condition` on the MainActor until true or timeout (grading and the
    /// engine reply are async) — mirrors `PlayGameLoopTests.wait`.
    private func wait(timeout: Double = 40, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }
        return condition()
    }

    /// Play 1. e4 on a fresh game and wait until the move is graded and the
    /// whole per-move pipeline (engine reply + coach note attempt) settled.
    private func playE4AndSettle(_ vm: PlayViewModel) async throws -> Bool {
        vm.skill = 1
        vm.newGame(asWhite: true)
        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2); vm.tap(e4)
        // `isCoaching` flips false at the very end of the move Task, after
        // `streamCoachNote` had its chance -- the deterministic settle point.
        return await wait { vm.lastVerdict != nil && !vm.engineThinking && !vm.isCoaching }
    }

    // MARK: AE1/AE2 — verdict + free comment on every tier

    @Test("a graded move yields a verdict AND a non-empty engine comment (coach enabled)")
    func gradedMoveYieldsCommentWithCoachEnabled() async throws {
        let vm = PlayViewModel.forTesting(coach: CoachOrchestrator(coach: mockStreaming("PRO NOTE")))
        vm.coachDisplayEnabled = true
        #expect(try await playE4AndSettle(vm))
        #expect(vm.lastVerdict?.moveSAN == "e4")
        #expect(vm.lastEngineComment?.isEmpty == false)
        #expect(!vm.topMoves.isEmpty)
    }

    // MARK: AE4 — Coach toggle off: engine content still lands, no coach traffic

    @Test("coach display off: verdict + comment populate, no coach note and no error")
    func coachOffStillGradesAndComments() async throws {
        let vm = PlayViewModel.forTesting(coach: CoachOrchestrator(coach: mockStreaming("PRO NOTE")))
        vm.coachDisplayEnabled = false
        #expect(try await playE4AndSettle(vm))
        #expect(vm.lastVerdict != nil)
        #expect(vm.lastEngineComment?.isEmpty == false)
        // The Pro prose path never ran -- no note, and no error either
        // (nothing was attempted, so nothing failed).
        #expect(vm.lastCoachNote == nil)
        #expect(vm.lastCoachError == nil)
    }

    // MARK: Entitlement gating — free App Store users never fire the doomed call

    @Test("non-entitled App Store channel: no per-move coach note is even attempted")
    func notEntitledSkipsCoachNoteEntirely() async throws {
        // The coach WOULD answer if called (mock always streams 200s) -- so a nil note
        // after settling proves the call was skipped client-side, not failed.
        let vm = PlayViewModel.forTesting(coach: CoachOrchestrator(coach: mockStreaming("PRO NOTE")))
        // Test binary never configures Purchases, so `isProActive == false` --
        // an App Store channel therefore gates (same seam as
        // `ProEntitlementStoreTests.proGatedOrchestrator`).
        vm.entitlementChannel = .appStore
        #expect(vm.isProEntitled == false)
        #expect(try await playE4AndSettle(vm))
        // Free tier still gets the full engine coaching...
        #expect(vm.lastVerdict != nil)
        #expect(vm.lastEngineComment?.isEmpty == false)
        // ...but no Pro prose request fired: no note, and no 403/error surfaced.
        #expect(vm.lastCoachNote == nil)
        #expect(vm.lastCoachError == nil)
    }

    @Test("dev channel (no entitlement required): the same coach note flows as before")
    func devChannelStillStreamsNote() async throws {
        let vm = PlayViewModel.forTesting(coach: CoachOrchestrator(coach: mockStreaming("PRO NOTE")))
        vm.entitlementChannel = .local
        #expect(vm.isProEntitled == true)
        #expect(try await playE4AndSettle(vm))
        // Control for the test above: with the gate open, the identical mock
        // coach DOES deliver the note -- so the nil note there is the gate.
        #expect(vm.lastCoachNote == "PRO NOTE")
    }

    // MARK: Clearing — the comment lives and dies with the verdict

    @Test("new game clears the engine comment along with the verdict")
    func newGameClearsComment() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playE4AndSettle(vm))
        #expect(vm.lastEngineComment != nil)
        vm.newGame(asWhite: true)
        #expect(vm.lastVerdict == nil)
        #expect(vm.lastEngineComment == nil)
    }

    @Test("undo clears the engine comment along with the verdict")
    func undoClearsComment() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playE4AndSettle(vm))
        _ = await wait { vm.moves.count >= 2 }
        vm.undoLastMove()
        #expect(vm.lastVerdict == nil)
        #expect(vm.lastEngineComment == nil)
    }

    // MARK: History browsing — the chip's verdict is rebuilt per browsed ply

    @Test("verdict(forPly:) returns the browsed user move's grade, nil for engine plies")
    func verdictForPlyMatchesRecords() async throws {
        let vm = PlayViewModel.forTesting()
        #expect(try await playE4AndSettle(vm))
        _ = await wait { vm.moves.count >= 2 }

        let browsed = try #require(vm.verdict(forPly: 0))
        #expect(browsed.moveSAN == "e4")
        #expect(browsed.classification == vm.moveRecords.first?.classification)
        // The engine's reply has no user grade to show.
        #expect(vm.verdict(forPly: 1) == nil)
        // Out of range never crashes.
        #expect(vm.verdict(forPly: 99) == nil)
    }
}
