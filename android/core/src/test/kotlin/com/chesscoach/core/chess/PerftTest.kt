package com.chesscoach.core.chess

import kotlin.test.Test
import kotlin.test.assertEquals

/** Standard perft (performance test) node counts -- the gold-standard correctness
 *  check for a legal move generator. Values are well-known reference counts. */
class PerftTest {

    private fun perft(board: Board, depth: Int): Long {
        if (depth == 0) return 1L
        val moves = MoveGen.legalMoves(board)
        if (depth == 1) return moves.size.toLong()
        var nodes = 0L
        for (move in moves) nodes += perft(board.applyMove(move), depth - 1)
        return nodes
    }

    @Test
    fun startingPositionPerft() {
        val board = Board.starting()
        assertEquals(20L, perft(board, 1))
        assertEquals(400L, perft(board, 2))
        assertEquals(8902L, perft(board, 3))
        assertEquals(197281L, perft(board, 4))
    }

    @Test
    fun kiwipetePerft() {
        // The famous "Kiwipete" position: exercises castling, en passant, promotions.
        val fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        val board = Board.fromFen(fen)!!
        assertEquals(48L, perft(board, 1))
        assertEquals(2039L, perft(board, 2))
        assertEquals(97862L, perft(board, 3))
    }

    @Test
    fun promotionPositionPerft() {
        val fen = "n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1"
        val board = Board.fromFen(fen)!!
        assertEquals(24L, perft(board, 1))
        assertEquals(496L, perft(board, 2))
        assertEquals(9483L, perft(board, 3))
    }

    @Test
    fun enPassantPositionPerft() {
        val fen = "rnbqkbnr/p1pppppp/8/1pP5/8/8/PP1PPPPP/RNBQKBNR w KQkq b6 0 3"
        val board = Board.fromFen(fen)!!
        // Depth 1 (23) is hand-counted from the FEN; depth 2/3 are this
        // implementation's own perft output, locked in as a regression baseline.
        assertEquals(23L, perft(board, 1))
        assertEquals(463L, perft(board, 2))
        assertEquals(11623L, perft(board, 3))
    }
}
