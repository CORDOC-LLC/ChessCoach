//  PlayScannedPositionTests.swift
//  Starting a game from a scanned board photo's FEN must hand the first move
//  to whichever side is actually on move in that FEN, not always the user --
//  unlike the standard start position, a scanned photo can be mid-game with
//  either side to move regardless of which side the user picked to play.

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
@Suite("Play: scanned position", .serialized)
struct PlayScannedPositionTests {

    /// White to move, user plays White -> it's the user's move.
    @Test("user's move when the scanned FEN's side-to-move matches the user's side")
    func userToMoveMatchesSideToMove() {
        let vm = PlayViewModel.forTesting()
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 4 3"
        vm.newGame(asWhite: true, startFEN: fen)

        #expect(vm.fen == fen)
        #expect(vm.status == "Your move")
    }

    /// White to move, user plays Black -> it's the engine's move, not the user's.
    @Test("engine's move when the scanned FEN's side-to-move is the opponent")
    func engineToMoveWhenSideMismatches() async {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 4 3"
        vm.newGame(asWhite: false, startFEN: fen)

        #expect(vm.status == "Engine is thinking…")
    }
}
