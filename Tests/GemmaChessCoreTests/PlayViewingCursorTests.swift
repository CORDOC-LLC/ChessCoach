//  PlayViewingCursorTests.swift
//  U6 — the viewing cursor lets the board show a past position without mutating the
//  live game, tap-to-move is disabled while viewing, and returning restores live.

import Testing
import ChessKit
@testable import GemmaChessCore

@MainActor
struct PlayViewingCursorTests {

    static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    static let afterE4E5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"

    /// A VM with a synthetic two-ply history (engine-free).
    private func seeded() -> PlayViewModel {
        let vm = PlayViewModel.forTesting()
        vm.fen = Self.afterE4E5
        vm.moves = ["e2e4", "e7e5"]
        vm.sanMoves = ["e4", "e5"]
        vm.fenHistory = [Self.start, Self.afterE4, Self.afterE4E5]
        return vm
    }

    @Test func viewingChangesDisplayFENNotLive() {
        let vm = seeded()
        vm.viewTo(ply: 1)        // before move 2: position after e4
        #expect(vm.isViewingHistory)
        #expect(vm.displayFEN == Self.afterE4)
        #expect(vm.fen == Self.afterE4E5)        // live untouched
        #expect(vm.moves == ["e2e4", "e7e5"])
    }

    @Test func returnToLiveRestoresLiveFEN() {
        let vm = seeded()
        vm.viewTo(ply: 0)
        #expect(vm.displayFEN == Self.start)
        vm.returnToLive()
        #expect(!vm.isViewingHistory)
        #expect(vm.displayFEN == vm.fen)
    }

    @Test func displayLastMoveTracksViewedNode() {
        let vm = seeded()
        vm.viewTo(ply: 1)        // outgoing move of node 1 is e7e5
        let lm = vm.displayLastMove
        #expect(lm?.from == .e7)
        #expect(lm?.to == .e5)
    }

    @Test func tapIsNoOpWhileViewing() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)       // engine-free for White
        vm.viewTo(ply: 0)               // browse the start position
        vm.tap(.e2)                     // would normally select e2
        #expect(vm.selected == nil)     // no-op while viewing
        #expect(vm.moves.isEmpty)
    }

    @Test func makingAMoveReturnsToLive() {
        // After newGame the cursor is nil; a fresh move keeps us live and appends.
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.tap(.d2)
        vm.tap(.d4)
        #expect(!vm.isViewingHistory)
        #expect(vm.moves.first == "d2d4")
        #expect(vm.fenHistory.count == 2)
    }
}
