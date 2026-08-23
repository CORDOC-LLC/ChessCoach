package com.chesscoach.core.chess

import kotlin.test.Test
import kotlin.test.assertEquals

class CapturedMaterialTest {

    @Test
    fun `starting position has no captures`() {
        val m = CapturedMaterial.from(Board.starting())
        assertEquals(emptyList(), m.capturedByWhite)
        assertEquals(emptyList(), m.capturedByBlack)
        assertEquals(0, m.delta)
    }

    @Test
    fun `a single pawn capture registers for the capturing side`() {
        // 1. e4 d5 2. exd5 -- White's pawn takes Black's d-pawn.
        var board = Board.starting()
        board = board.applyMove(ChessLogic.parseUci(board, "e2e4")!!)
        board = board.applyMove(ChessLogic.parseUci(board, "d7d5")!!)
        board = board.applyMove(ChessLogic.parseUci(board, "e4d5")!!)

        val m = CapturedMaterial.from(board)
        assertEquals(listOf('p'), m.capturedByWhite)
        assertEquals(emptyList(), m.capturedByBlack)
        assertEquals(1, m.delta)
    }
}
