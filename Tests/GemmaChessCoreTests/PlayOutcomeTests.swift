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

    @Test("resigning is .loss and records exactly one loss in stats")
    func resigning() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        let before = vm.stats
        vm.resign()
        #expect(vm.outcome == .loss)
        #expect(vm.stats.losses == before.losses + 1)

        // Resigning an already-finished game is a no-op -- no double count.
        vm.resign()
        #expect(vm.stats.losses == before.losses + 1)
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
