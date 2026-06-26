//  PlayMoveListTests.swift
//  U4 — the pure move-list shaping: SAN plies pair into numbered rows, an odd
//  count leaves the last black cell empty, and the active ply resolves correctly.

import Testing
@testable import GemmaChessCore

@MainActor
struct PlayMoveListTests {

    @Test func fourPlyMakesTwoFullRows() {
        let san = ["e4", "e5", "Nf3", "Nc6"]
        let rows = MoveListFormatter.rows(from: san)
        #expect(rows == [
            MoveRow(number: 1, white: "e4", black: "e5"),
            MoveRow(number: 2, white: "Nf3", black: "Nc6"),
        ])
    }

    @Test func oddPlyLeavesLastBlackEmpty() {
        let rows = MoveListFormatter.rows(from: ["e4", "e5", "Nf3"])
        #expect(rows.count == 2)
        #expect(rows[1] == MoveRow(number: 2, white: "Nf3", black: nil))
    }

    @Test func activePlyTracksLiveAndViewing() {
        // Live: the latest ply is current.
        #expect(MoveListFormatter.activePly(viewingPly: nil, moveCount: 4) == 3)
        #expect(MoveListFormatter.activePly(viewingPly: nil, moveCount: 0) == nil)
        // Viewing: the cursor wins.
        #expect(MoveListFormatter.activePly(viewingPly: 1, moveCount: 4) == 1)
    }

    @Test func sanAccumulatesAtMoveTime() {
        // The VM appends SAN as moves are made (no replay). Drive one user move and
        // confirm the SAN + history grew in step (white's first move, no engine wait).
        let vm = PlayViewModel()
        vm.newGame(asWhite: true)
        vm.tap(.e2)
        vm.tap(.e4)
        #expect(vm.moves.first == "e2e4")
        #expect(vm.sanMoves.first == "e4")
        #expect(vm.fenHistory.count == 2)        // start + after e4
    }
}
