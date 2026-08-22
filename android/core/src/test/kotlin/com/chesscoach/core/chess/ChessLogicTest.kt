package com.chesscoach.core.chess

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChessLogicTest {

    @Test
    fun fenRoundTrip() {
        assertEquals(Board.STARTING_FEN, ChessLogic.normalizedFEN(Board.STARTING_FEN))
        assertNull(ChessLogic.normalizedFEN("not a fen"))
    }

    @Test
    fun scholarsMateIsCheckmate() {
        var fen = Board.STARTING_FEN
        for (san in listOf("e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#")) {
            fen = ChessLogic.fenAfterMove(san, fen) ?: error("failed to apply $san from $fen")
        }
        assertEquals(GameStatus.CHECKMATE, ChessLogic.status(fen))
    }

    @Test
    fun stalemateDetected() {
        // Classic stalemate: black king on a8 has no legal moves and is not in check.
        val fen = "k7/8/1Q6/8/8/8/8/1K6 b - - 0 1"
        assertEquals(GameStatus.STALEMATE, ChessLogic.status(fen))
    }

    @Test
    fun castlingRoundTrip() {
        val fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        val afterCastle = ChessLogic.fenAfterMove("O-O", fen)
        assertEquals("r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1", afterCastle)
    }

    @Test
    fun enPassantCapture() {
        val fen = "rnbqkbnr/p1pppppp/8/1pP5/8/8/PP1PPPPP/RNBQKBNR w KQkq b6 0 3"
        val after = ChessLogic.fenAfterMove("cxb6", fen)
        assertTrue(after != null && after.startsWith("rnbqkbnr/p1pppppp/1P6/8"))
    }

    @Test
    fun uciSanRoundTrip() {
        val uci = ChessLogic.uciFromSan("Nf3", Board.STARTING_FEN)
        assertEquals("g1f3", uci)
        val san = ChessLogic.sanFromUci("g1f3", Board.STARTING_FEN)
        assertEquals("Nf3", san)
    }

    @Test
    fun pgnMainlineParsesAndReplays() {
        val pgn = """
            [Event "Test"]
            [Result "1-0"]

            1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0
        """.trimIndent()
        val sans = Pgn.mainlineSan(pgn)
        assertEquals(listOf("e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"), sans)
        val finalFen = Pgn.finalFen(pgn)
        assertEquals(GameStatus.CHECKMATE, finalFen?.let { ChessLogic.status(it) })
    }

    @Test
    fun pgnWithCommentsAndVariationsStripped() {
        val pgn = "1. e4 {best by test} e5 (1... c5 2. Nf3) 2. Nf3 \$1 Nc6 *"
        assertEquals(listOf("e4", "e5", "Nf3", "Nc6"), Pgn.mainlineSan(pgn))
    }
}
