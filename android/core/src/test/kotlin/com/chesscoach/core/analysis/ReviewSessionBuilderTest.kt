package com.chesscoach.core.analysis

import com.chesscoach.core.chess.PlayMoveRecord
import com.chesscoach.core.chess.SavedGame
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReviewSessionBuilderTest {

    private fun fens(n: Int) = (0..n).map { "fen$it" }

    @Test
    fun `canBuild requires at least two plies and a full winAfterMover`() {
        val tooShort = SavedGame(
            id = "a", startedAt = 0, updatedAt = 0, playerIsWhite = true, startFen = "fen0",
            moves = listOf("e2e4"), sanMoves = listOf("e4"), fenHistory = fens(1),
            skill = 10, isGameOver = false, resultText = null, openingName = null, openingEco = null,
            moveRecords = emptyList(), winAfterMover = listOf(55.0),
        )
        assertTrue(!ReviewSessionBuilder.canBuild(tooShort))

        val missingWinData = tooShort.copy(
            moves = listOf("e2e4", "e7e5"), sanMoves = listOf("e4", "e5"), fenHistory = fens(2),
            winAfterMover = listOf(55.0), // only 1 entry for 2 plies -- incomplete
        )
        assertTrue(!ReviewSessionBuilder.canBuild(missingWinData))
    }

    @Test
    fun `build with no mistakes produces an empty mistakes list and a full timeline`() {
        val record = PlayMoveRecord(
            moveNumber = 1, san = "e4", classification = "best",
            winBefore = 50.0, winAfter = 55.0, betterSan = null, bestUci = null, fen = null,
        )
        val game = SavedGame(
            id = "g1", startedAt = 0, updatedAt = 0, playerIsWhite = true, startFen = "fen0",
            moves = listOf("e2e4", "e7e5"), sanMoves = listOf("e4", "e5"), fenHistory = fens(2),
            skill = 10, isGameOver = false, resultText = null, openingName = "Open Game", openingEco = "C20",
            moveRecords = listOf(record), winAfterMover = listOf(55.0, 52.0),
        )

        val session = ReviewSessionBuilder.build(game)
        assertTrue(session != null)
        session!!

        assertEquals("white", session.player)
        assertTrue(session.mistakes.isEmpty())
        assertEquals(1, session.allMoves.size)
        assertEquals("best", session.allMoves[0].classification)
        assertEquals(3, session.timeline.size) // 0..plyCount inclusive
        assertTrue(abs(session.timeline[0].winWhite - 50.0) < 1e-9)
        assertEquals(1, session.timeline[0].ply)
        assertEquals("e4", session.timeline[0].moveSan)
        assertNull(session.timeline[2].ply) // final node carries no outgoing move
    }

    @Test
    fun `build flags a blunder and links it into the mistakes list`() {
        val bestMove = PlayMoveRecord(
            moveNumber = 1, san = "e4", classification = "best",
            winBefore = 50.0, winAfter = 55.0, betterSan = null, bestUci = null, fen = null,
        )
        val blunder = PlayMoveRecord(
            moveNumber = 2, san = "Qh5", classification = "blunder",
            winBefore = 55.0, winAfter = 10.0, betterSan = "Nf3", bestUci = null, fen = null,
        )
        val game = SavedGame(
            id = "g2", startedAt = 0, updatedAt = 0, playerIsWhite = true, startFen = "fen0",
            moves = listOf("e2e4", "e7e5", "d1h5", "b8c6"),
            sanMoves = listOf("e4", "e5", "Qh5", "Nc6"),
            fenHistory = fens(4),
            skill = 10, isGameOver = true, resultText = "You resigned.",
            openingName = null, openingEco = null,
            moveRecords = listOf(bestMove, blunder),
            winAfterMover = listOf(55.0, 45.0, 10.0, 8.0),
        )

        val session = ReviewSessionBuilder.build(game)
        assertTrue(session != null)
        session!!

        assertEquals(1, session.mistakes.size)
        val mistake = session.mistakes[0]
        assertEquals("blunder", mistake.classification)
        assertEquals("Qh5", mistake.moveSan)
        assertEquals("Nf3", mistake.bestMoveSan)
        assertTrue(mistake.comment.contains("Better was Nf3"))
        assertEquals(3, mistake.ply) // white's 2nd move is ply 3 (1-based)

        // The timeline node at that ply links back to the same mistake index.
        val node = session.timeline.first { it.ply == 3 }
        assertEquals(0, node.mistakeIndex)

        // Resigning as White with no PGN-style result recorded maps to a loss.
        assertEquals("0-1", session.result)
        assertEquals("loss", ReviewSessionBuilder.playerResultWord(game))
    }

    @Test
    fun `canBuild is false and build returns null when winAfterMover is entirely absent`() {
        val game = SavedGame(
            id = "g3", startedAt = 0, updatedAt = 0, playerIsWhite = true, startFen = "fen0",
            moves = listOf("e2e4", "e7e5"), sanMoves = listOf("e4", "e5"), fenHistory = fens(2),
            skill = 10, isGameOver = false, resultText = null, openingName = null, openingEco = null,
            moveRecords = emptyList(), winAfterMover = null,
        )
        assertTrue(!ReviewSessionBuilder.canBuild(game))
        assertNull(ReviewSessionBuilder.build(game))
    }
}
