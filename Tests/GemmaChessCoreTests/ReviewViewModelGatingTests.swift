//  ReviewViewModelGatingTests.swift
//  U4: the free-tier ply gate on ReviewViewModel. Drives a hand-built,
//  synthetic 16-ply SavedGame straight through ReviewSessionBuilder (pure,
//  no Stockfish, no chess-legality validation -- see ReviewSessionBuilder's
//  own header) so these tests run instantly and don't depend on a real
//  played game. Entitlement state is driven via ProEntitlementStore's debug
//  simulation, always reset to `.off` afterward since it's a UserDefaults-
//  backed singleton shared across this `.serialized` file's tests.

import Foundation
import Testing
@testable import GemmaChessCore

@MainActor
@Suite("ReviewViewModel: free-tier ply gate (U4)", .serialized)
struct ReviewViewModelGatingTests {

    /// A 16-ply (8 full move) game as White, with a mistake at ply 5 (inside
    /// the 12-ply free limit) and a blunder at ply 13 (just past it) -- lets
    /// a single fixture exercise both the "in range" and "locked" mistake paths.
    private func longSavedGame() -> SavedGame {
        let plyCount = 16
        let moves = (0..<plyCount).map { "u\($0)" }
        let sanMoves = (0..<plyCount).map { "M\($0)" }
        let fenHistory = (0...plyCount).map { "FEN\($0)" }
        let winAfterMover = (0..<plyCount).map { i -> Double in
            i == 4 ? 40.0 : (i == 12 ? 20.0 : 55.0)
        }
        let userPlyIndices = stride(from: 0, to: plyCount, by: 2) // White's plies: 0,2,4,...,14
        let moveRecords = userPlyIndices.map { idx -> CoachPromptBuilder.PlayMoveRecord in
            let classification = idx == 4 ? "mistake" : (idx == 12 ? "blunder" : "good")
            return CoachPromptBuilder.PlayMoveRecord(
                moveNumber: (idx / 2) + 1, san: sanMoves[idx], classification: classification,
                winBefore: 50, winAfter: 50, betterSan: nil)
        }
        return SavedGame(
            id: UUID(), startedAt: Date(), updatedAt: Date(), playerIsWhite: true,
            startFEN: fenHistory[0], moves: moves, sanMoves: sanMoves, fenHistory: fenHistory,
            skill: 6, isGameOver: false, resultText: nil, openingName: nil, openingECO: nil,
            moveNotes: [:], gameSummary: nil, moveRecords: moveRecords, winAfterMover: winAfterMover)
    }

    private func makeVM(access: ProEntitlementStore.DebugProSimulation) -> ReviewViewModel {
        ProEntitlementStore.shared.debugProSimulation = access
        let vm = ReviewViewModel()
        let saved = longSavedGame()
        let session = ReviewSessionBuilder.build(from: saved)
        #expect(session != nil)
        vm.session = session
        vm.currentNode = 0
        return vm
    }

    @Test("hasFullReviewAccess true (pro) -- goto reaches the true last node, no clamping")
    func fullAccessNoClamping() {
        let vm = makeVM(access: .pro)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        #expect(vm.hasFullReviewAccess == true)
        vm.goto(node: vm.nodeCount - 1)
        #expect(vm.currentNode == vm.nodeCount - 1)
        #expect(vm.lockedMoveCount == 0)
    }

    @Test("hasFullReviewAccess true (lifetime) -- also no clamping")
    func lifetimeAccessNoClamping() {
        let vm = makeVM(access: .lifetime)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        #expect(vm.hasFullReviewAccess == true)
        vm.goto(node: vm.nodeCount - 1)
        #expect(vm.currentNode == vm.nodeCount - 1)
    }

    @Test("locked -- goto clamps to node 11 (ply 12), never reaches ply 13's verdict")
    func lockedClampsToNode11() {
        let vm = makeVM(access: .free)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        #expect(vm.hasFullReviewAccess == false)
        vm.goto(node: vm.nodeCount - 1) // attempt to reach node 16
        #expect(vm.currentNode == 11)
        // The off-by-one regression this guards against: node 11's ply is 12,
        // never 13. Ply 12 is Black's move (an even ply), so `verdict` (which
        // only resolves for the reviewed side, White) is correctly nil here --
        // check the node's own `ply` instead, the field the clamp is about.
        #expect(vm.currentTimelineNode?.ply == 12)
    }

    @Test("locked -- lockedMoveCount reflects the moves beyond the cap")
    func lockedMoveCountReflectsRemainder() {
        let vm = makeVM(access: .free)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        // nodeCount - 1 == 16 total plies; free cap is 12 -> 4 locked.
        #expect(vm.lockedMoveCount == 4)
    }

    @Test("locked -- gotoMistake within the free limit navigates normally")
    func gotoMistakeWithinLimitNavigates() {
        let vm = makeVM(access: .free)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        let mistakeIndex = vm.session?.mistakes.firstIndex { $0.ply == 5 }
        #expect(mistakeIndex != nil)
        guard let mistakeIndex else { return }
        vm.gotoMistake(index: mistakeIndex)
        #expect(vm.showReviewUnlockPaywall == false)
        #expect(vm.currentNode == 4) // ply 5's position is node 4
    }

    @Test("locked -- gotoMistake beyond the free limit shows the unlock paywall, does not navigate")
    func gotoMistakeBeyondLimitShowsPaywall() {
        let vm = makeVM(access: .free)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        let before = vm.currentNode
        let mistakeIndex = vm.session?.mistakes.firstIndex { $0.ply == 13 }
        #expect(mistakeIndex != nil)
        guard let mistakeIndex else { return }
        vm.gotoMistake(index: mistakeIndex)
        #expect(vm.showReviewUnlockPaywall == true)
        #expect(vm.currentNode == before) // no navigation happened
    }

    @Test("locked -- winValues still shows the full game (teaser), navigation stays capped")
    func winValuesFullEvenWhenLocked() {
        let vm = makeVM(access: .free)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        // The graph itself is never truncated -- only goto/gotoMistake clamp.
        #expect(vm.winValues.count == vm.nodeCount)
        vm.goto(node: vm.nodeCount - 1)
        #expect(vm.currentNode == 11) // still clamped to the free boundary
    }

    @Test("unlocked -- winValues includes the full game")
    func winValuesFullWhenUnlocked() {
        let vm = makeVM(access: .pro)
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        #expect(vm.winValues.count == vm.nodeCount)
    }

    @Test("entitlement flips live mid-session -- a subsequent next() advances past the old clamp")
    func liveEntitlementFlipUnclampsImmediately() {
        let vm = makeVM(access: .free)
        vm.goto(node: vm.nodeCount - 1)
        #expect(vm.currentNode == 11)

        ProEntitlementStore.shared.debugProSimulation = .lifetime
        defer { ProEntitlementStore.shared.debugProSimulation = .off }

        vm.next()
        #expect(vm.currentNode == 12) // no longer clamped
    }
}
