package com.chesscoach.core.chess

/**
 * Free, template-based one-line engine comment about the move just played --
 * a simplified Kotlin port of `Sources/GemmaChessCore/Coach/
 * MoveCommentTemplates.swift`. No LLM, no network: runs on facts the play
 * loop already has (the two boards, the classification, the better move).
 *
 * Simplified from the iOS version: skips forced-mate-in-N phrasing and the
 * "leaves your piece hanging" SEE-lite check (both need attacker/defender
 * enumeration this build's `MoveGen` doesn't expose yet) -- capture
 * detection and the classification-driven templates below already cover
 * the large majority of real-game moments.
 */
object MoveCommentTemplates {

    private const val GENERIC = "A reasonable move -- keep building your position."

    private val pieceNames = mapOf(
        PieceType.PAWN to "pawn", PieceType.KNIGHT to "knight", PieceType.BISHOP to "bishop",
        PieceType.ROOK to "rook", PieceType.QUEEN to "queen", PieceType.KING to "king",
    )

    fun comment(
        boardBefore: Board,
        boardAfter: Board,
        move: Move,
        classification: MoveGrade,
        betterSan: String?,
    ): String {
        val better = betterSan?.takeIf { it.isNotEmpty() }

        if (GameStatus.of(boardAfter) == GameStatus.CHECKMATE) return "Checkmate -- game over."

        // A capture that wins material, only when the verdict doesn't contradict it.
        val capturedType = boardBefore.pieceAt(move.to)?.type
        if (classification != MoveGrade.MISTAKE && classification != MoveGrade.BLUNDER && capturedType != null) {
            val name = pieceNames[capturedType] ?: "piece"
            return "That wins a $name -- nicely spotted."
        }

        return when (classification) {
            MoveGrade.BLUNDER -> if (better != null) "A blunder -- $better kept the pressure." else "A blunder -- that gives away too much."
            MoveGrade.MISTAKE -> if (better != null) "A mistake -- $better was stronger." else "A mistake -- there was a stronger option here."
            MoveGrade.INACCURACY -> if (better != null) "A little imprecise -- $better was more accurate." else "A little imprecise -- a sharper move was available."
            MoveGrade.BEST -> if (better != null) "Just as good as $better, the engine's pick." else "The engine's top choice -- well played."
            MoveGrade.EXCELLENT -> "An excellent move."
            MoveGrade.GOOD -> "A good, solid move."
        }
    }
}
