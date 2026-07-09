//  PuzzleViewModelTests.swift
//  The puzzle-solving loop: the setup move auto-plays, a wrong-but-legal
//  attempt is rejected without advancing, and a correct attempt (here a
//  2-ply mate-in-1, so no auto-reply delay is involved) solves the puzzle
//  and records progress. Real data from the curated Lichess pack, so this
//  also doubles as a sanity check on the curation pipeline's move legality.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("PuzzleViewModel")
struct PuzzleViewModelTests {

    // A real 2-ply mate-in-1 from PuzzleData/packs/mateIn1.json: black plays
    // the setup move f8g7, then White mates with the queen: g2g7.
    private let mateIn1 = Puzzle(
        id: "00lhe",
        fen: "r2q1b1k/ppp3Bp/3pPp2/2n1n3/4P2P/1B3P2/PPP3Q1/2K3RR b - - 0 23",
        moves: ["f8g7", "g2g7"],
        rating: 399,
        themes: ["kingsideAttack", "mate", "mateIn1", "middlegame", "oneMove"]
    )

    @Test("starting a session auto-plays the setup move and orients the board to the solver")
    func startSessionAppliesSetupMove() {
        let vm = PuzzleViewModel.forTesting()
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [mateIn1]))

        let expectedFEN = ChessLogic.fen(afterMove: "f8g7", fromFEN: mateIn1.fen)
        #expect(vm.fen == expectedFEN)
        #expect(vm.solverIsWhite)          // black played the setup move -> White solves
        #expect(vm.orientation == .white)
        #expect(vm.status == "Find the best move.")
        #expect(vm.feedback == nil)
    }

    @Test("a wrong-but-legal move is rejected without advancing the puzzle")
    func wrongMoveDoesNotAdvance() throws {
        let vm = PuzzleViewModel.forTesting()
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [mateIn1]))
        let positionAfterSetup = vm.fen

        // Any legal move that isn't the g2-g7 mate.
        let dests = ChessLogic.legalDestinations(forFEN: positionAfterSetup)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        let move = try #require(wrong)

        vm.tap(move.from)
        vm.tap(move.to)

        #expect(vm.feedback == .incorrect)
        #expect(vm.fen == positionAfterSetup)   // nothing applied
        #expect(vm.currentPuzzle?.id == mateIn1.id)
    }

    @Test("the correct move solves the puzzle and records progress")
    func correctMoveSolves() throws {
        let vm = PuzzleViewModel.forTesting()
        vm.startSession(pack: PuzzlePack(theme: "mateIn1", puzzles: [mateIn1]))

        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        vm.tap(g2)
        vm.tap(g7)

        #expect(vm.feedback == .solved)
        #expect(vm.status == "Solved!")
        #expect(vm.sessionSolvedCount == 1)
        #expect(vm.isSessionComplete == false)   // one puzzle, but session isn't "advanced past" yet

        // nextPuzzle() on a single-puzzle pack ends the session.
        vm.nextPuzzle()
        #expect(vm.currentPuzzle == nil)
        #expect(vm.isSessionComplete)
    }
}
