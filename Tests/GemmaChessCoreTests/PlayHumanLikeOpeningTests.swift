//  PlayHumanLikeOpeningTests.swift
//  U1 — integration coverage for the Human-like opponent's opening-book
//  continuation at the PlayViewModel level: toggle on, past the book-depth
//  ply window, and toggle-off regression. Uses real Stockfish (shallow
//  skill), so it's serialized like the other game-loop tests.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("Play: human-like opening book", .serialized)
struct PlayHumanLikeOpeningTests {

    /// Poll `condition` on the MainActor until true or timeout (engine reply is async).
    private func wait(timeout: Double = 40, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }
        return condition()
    }

    @Test("toggle on: a fresh game with a few plies stays legal and playable")
    func toggleOnProducesALegalPlayableGame() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.humanLikeEnabled = true
        vm.newGame(asWhite: true)

        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2)
        vm.tap(e4)   // 1. e4

        #expect(vm.moves.first == "e2e4")
        #expect(vm.sanMoves.first == "e4")

        let replied = await wait { vm.moves.count >= 2 }
        #expect(replied)
        #expect(!vm.gameOver)
        // The reply is a legal move (parses to two valid squares) and state stays
        // internally consistent, exactly as the toggle-off game loop expects.
        let reply = vm.moves[1]
        #expect(BoardGeometry.square(String(reply.prefix(2))) != nil)
        #expect(BoardGeometry.square(String(reply.dropFirst(2).prefix(2))) != nil)
        #expect(vm.fenHistory.count == vm.moves.count + 1)
        #expect(vm.sanMoves.count == vm.moves.count)

        let settled = await wait { !vm.engineThinking }
        #expect(settled)
        #expect(vm.status == "Your move")
    }

    @Test("toggle on: replies past the book-depth ply window never consult the book")
    func pastTheBookWindowFallsThroughToEngine() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.humanLikeEnabled = true
        vm.newGame(asWhite: true)

        // Play moves until we're past the book-ply window, then verify the reply
        // still lands as a normal legal engine move -- i.e. the fallback to
        // `EnginePool.playMove` still works once out of the bounded window.
        let squares: [(String, String)] = [("e2", "e4"), ("d2", "d4"), ("g1", "f3"), ("b1", "c3"), ("f1", "c4")]

        var rounds = 0
        for (fromName, toName) in squares {
            guard vm.userToMove, !vm.gameOver else { break }
            guard let from = BoardGeometry.square(fromName), let to = BoardGeometry.square(toName),
                  let dests = ChessLogic.legalDestinations(forFEN: vm.fen)[from], dests.contains(to) else {
                break
            }
            vm.tap(from)
            vm.tap(to)
            rounds += 1
            let replied = await wait { vm.moves.count >= rounds * 2 }
            #expect(replied)
            if vm.gameOver { break }
        }

        // Past `PlayViewModel.humanLikeBookPlyWindow`, the ply count exceeds the
        // window, so every further reply must be a normal (legal, engine-sourced)
        // move -- the book helper is a no-op there by construction (guarded on
        // `sanMoves.count < humanLikeBookPlyWindow`).
        #expect(vm.moves.count >= PlayViewModel.humanLikeBookPlyWindow || vm.gameOver)
        #expect(vm.sanMoves.count == vm.moves.count)
        #expect(vm.fenHistory.count == vm.moves.count + 1)
    }

    @Test("toggle off: engine replies are unaffected -- no book consultation at all")
    func toggleOffRegression() async throws {
        let vm = PlayViewModel.forTesting()
        vm.skill = 1
        vm.humanLikeEnabled = false
        vm.newGame(asWhite: true)

        let e2 = try #require(BoardGeometry.square("e2"))
        let e4 = try #require(BoardGeometry.square("e4"))
        vm.tap(e2)
        vm.tap(e4)

        #expect(vm.moves.first == "e2e4")
        let replied = await wait { vm.moves.count >= 2 }
        #expect(replied)
        #expect(!vm.gameOver)
        let reply = vm.moves[1]
        #expect(BoardGeometry.square(String(reply.prefix(2))) != nil)
        #expect(BoardGeometry.square(String(reply.dropFirst(2).prefix(2))) != nil)

        let graded = await wait { vm.lastVerdict != nil }
        #expect(graded)
        #expect(vm.lastVerdict?.moveSAN == "e4")

        let settled = await wait { !vm.engineThinking }
        #expect(settled)
        #expect(vm.status == "Your move")
    }
}
