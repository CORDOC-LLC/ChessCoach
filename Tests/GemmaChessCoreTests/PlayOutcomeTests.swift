//  PlayOutcomeTests.swift
//  PlayViewModel.outcome drives the game-over banner's icon/color -- derived
//  from the exact resultText strings checkGameOver()/resign() set.

import Testing
@testable import GemmaChessCore

@MainActor
@Suite("Play: outcome")
struct PlayOutcomeTests {

    @Test("nil while the game is still live")
    func nilWhileLive() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        #expect(vm.outcome == nil)
    }

    @Test("a winning checkmate is .win")
    func winningCheckmate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Checkmate — you win! 🎉"
        #expect(vm.outcome == .win)
    }

    @Test("a losing checkmate is .loss")
    func losingCheckmate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Checkmate — you lose."
        #expect(vm.outcome == .loss)
    }

    @Test("resigning is .loss")
    func resigning() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.resign()
        #expect(vm.outcome == .loss)
    }

    @Test("stalemate is .draw")
    func stalemate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Stalemate — it's a draw."
        #expect(vm.outcome == .draw)
    }
}
