package com.chesscoach.core.analysis

import com.chesscoach.core.chess.ChessLogic
import com.chesscoach.core.chess.PlayMoveRecord
import com.chesscoach.core.chess.SavedGame
import com.chesscoach.core.eval.Evaluation

private val MISTAKE_CLASSIFICATIONS = setOf("inaccuracy", "mistake", "blunder")

/**
 * Builds a full [ReviewSession] (the win-graph + played-vs-best timeline the
 * review screen shows) straight from a Play-mode [SavedGame]'s already-
 * captured live data -- zero engine calls. Port of iOS's
 * `ReviewSessionBuilder.build(from:)`; follows the same math exactly.
 */
object ReviewSessionBuilder {

    /** Whether [savedGame] has everything needed: `winAfterMover` covering
     *  every ply, and at least two plies played. A partially-filled array is
     *  treated as fully unavailable rather than building a session with a
     *  gap in its win-graph. */
    fun canBuild(savedGame: SavedGame): Boolean {
        if (savedGame.moves.size < 2) return false
        return savedGame.winAfterMover?.size == savedGame.moves.size
    }

    fun build(savedGame: SavedGame): ReviewSession? {
        if (!canBuild(savedGame)) return null
        val winAfterMover = savedGame.winAfterMover ?: return null
        val plyCount = savedGame.moves.size
        val side = if (savedGame.playerIsWhite) "white" else "black"
        val result = playResult(savedGame.resultText, savedGame.playerIsWhite)
        val pgn = pgnFrom(savedGame, result)

        val headers = buildMap {
            put("White", if (savedGame.playerIsWhite) "Me" else "Stockfish")
            put("Black", if (savedGame.playerIsWhite) "Stockfish" else "Me")
            put("Result", result)
            if (!savedGame.openingName.isNullOrEmpty()) put("Opening", savedGame.openingName)
            if (!savedGame.openingEco.isNullOrEmpty()) put("ECO", savedGame.openingEco)
        }

        // Mover-relative winBefore at ply i is the previous ply's winAfter,
        // perspective-flipped (the mover alternates every ply). Ply 0 has no
        // previous ply -- 50.0 is the standard-starting-position estimate.
        fun winBefore(i: Int): Double = if (i == 0) 50.0 else 100.0 - winAfterMover[i - 1]

        // Every ply the reviewed side played, in order, zipped against
        // moveRecords -- moveRecords holds only the user's plies with
        // neither its own UCI nor ply index, so position is the only link.
        val userPlyIndices = (0 until plyCount).filter { (it % 2 == 0) == savedGame.playerIsWhite }
        val recordByPly = mutableMapOf<Int, PlayMoveRecord>()
        userPlyIndices.zip(savedGame.moveRecords).forEach { (idx, record) ->
            if (savedGame.sanMoves.getOrNull(idx) == record.san) recordByPly[idx] = record
        }

        val whiteAccs = mutableListOf<Double>()
        val blackAccs = mutableListOf<Double>()
        val allMoves = mutableListOf<MoveReview>()

        for (i in 0 until plyCount) {
            val isWhiteMove = i % 2 == 0
            val wb = winBefore(i)
            val wa = winAfterMover[i]
            val acc = Evaluation.moveAccuracy(wb, wa)
            if (isWhiteMove) whiteAccs.add(acc) else blackAccs.add(acc)

            // Only the reviewed side's moves feed allMoves/mistakes.
            val record = recordByPly[i] ?: continue
            val fenBefore = savedGame.fenHistory[i]
            val fenAfter = record.fen ?: savedGame.fenHistory.getOrNull(i + 1) ?: fenBefore
            val bestSan = record.bestUci?.let { ChessLogic.sanFromUci(it, fenBefore) } ?: record.betterSan
            var comment = ""
            if (record.classification in MISTAKE_CLASSIFICATIONS) {
                comment = "Win chance ${fmt1(wb)}% → ${fmt1(wa)}%."
                if (bestSan != null) comment += " Better was $bestSan."
            }
            allMoves.add(
                MoveReview(
                    ply = i + 1, moveNumber = (i / 2) + 1, color = if (isWhiteMove) "white" else "black",
                    moveSan = record.san, moveUci = savedGame.moves[i],
                    fenBefore = fenBefore, fenAfter = fenAfter,
                    winBefore = Evaluation.round1(wb), winAfter = Evaluation.round1(wa),
                    winSwing = Evaluation.round1(wb - wa),
                    classification = record.classification,
                    bestMoveSan = bestSan ?: record.san,
                    accuracy = Evaluation.round1(acc), comment = comment,
                )
            )
        }

        val mistakes = allMoves.filter { it.classification in MISTAKE_CLASSIFICATIONS }
        val mistakeIndexByPly = mistakes.withIndex().associate { (idx, m) -> m.ply to idx }

        // Timeline: one node per position, 0..plyCount.
        val timeline = (0..plyCount).map { k ->
            val isFinal = k == plyCount
            val fen = savedGame.fenHistory[k]
            val turnIsWhite = k % 2 == 0
            val winWhiteAtNode = if (k == 0) {
                50.0
            } else {
                val priorMoverIsWhite = (k - 1) % 2 == 0
                if (priorMoverIsWhite) winAfterMover[k - 1] else 100.0 - winAfterMover[k - 1]
            }
            if (isFinal) {
                TimelineNode(
                    node = k, fen = fen, winWhite = Evaluation.round1(winWhiteAtNode),
                    color = if (turnIsWhite) "white" else "black", moveNumber = (k / 2) + 1,
                )
            } else {
                val ply = k + 1
                val record = recordByPly[k]
                TimelineNode(
                    node = k, fen = fen, winWhite = Evaluation.round1(winWhiteAtNode),
                    color = if (turnIsWhite) "white" else "black", moveNumber = (k / 2) + 1,
                    ply = ply, moveSan = savedGame.sanMoves[k], moveUci = savedGame.moves[k],
                    bestUci = record?.bestUci,
                    bestSan = record?.bestUci?.let { ChessLogic.sanFromUci(it, fen) } ?: record?.betterSan,
                    isMyMove = record != null,
                    classification = record?.classification,
                    mistakeIndex = mistakeIndexByPly[ply],
                )
            }
        }

        return ReviewSession(
            pgn = pgn, player = side, headers = headers, result = result,
            accuracyWhite = Evaluation.round1(Evaluation.aggregateAccuracy(whiteAccs)),
            accuracyBlack = Evaluation.round1(Evaluation.aggregateAccuracy(blackAccs)),
            allMoves = allMoves, mistakes = mistakes, timeline = timeline,
        )
    }

    /** "you win"/"you lose"/"You resigned."/anything else -> PGN-style result
     *  code. Mirrors iOS `HistoryStore.playResult`'s text-sniffing. */
    fun playResult(text: String?, playerIsWhite: Boolean): String {
        if (text == null) return "*"
        if (text.contains("you win")) return if (playerIsWhite) "1-0" else "0-1"
        if (text.contains("you lose") || text == "You resigned.") return if (playerIsWhite) "0-1" else "1-0"
        return "1/2-1/2"
    }

    /** Player-relative outcome word for a "My games" row: "win"/"loss"/"draw",
     *  or null while the game is still in progress. */
    fun playerResultWord(savedGame: SavedGame): String? {
        if (!savedGame.isGameOver) return null
        val result = playResult(savedGame.resultText, savedGame.playerIsWhite)
        return when (result) {
            "1-0" -> if (savedGame.playerIsWhite) "win" else "loss"
            "0-1" -> if (savedGame.playerIsWhite) "loss" else "win"
            "1/2-1/2" -> "draw"
            else -> null
        }
    }

    /** A minimal, reconstructed PGN body for a Play game -- no real headers
     *  exist since it was never imported. Good enough for review; not a
     *  byte-perfect archival PGN. */
    fun pgnFrom(savedGame: SavedGame, result: String): String {
        val lines = StringBuilder()
        lines.append("[White \"${if (savedGame.playerIsWhite) "Me" else "Stockfish"}\"]\n")
        lines.append("[Black \"${if (savedGame.playerIsWhite) "Stockfish" else "Me"}\"]\n")
        lines.append("[Result \"$result\"]\n\n")
        val body = StringBuilder()
        savedGame.sanMoves.forEachIndexed { i, san ->
            if (i % 2 == 0) body.append("${i / 2 + 1}. ")
            body.append(san).append(' ')
        }
        body.append(result)
        lines.append(body)
        return lines.toString()
    }

    private fun fmt1(x: Double): String = "%.1f".format(Evaluation.round1(x))
}
