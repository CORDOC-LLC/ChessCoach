package com.chesscoach.core.chess

/**
 * Free, template-based "why" rationale for the on-demand hint -- a simplified
 * Kotlin port of `Sources/GemmaChessCore/Coach/HintRationaleTemplates.swift`.
 * No LLM, no network.
 *
 * Simplified from the iOS version: skips the "gets a piece out of danger"
 * defensive-move classification (needs threat/attacker enumeration this
 * build's `MoveGen` doesn't expose yet). Mate-in-N and capture detection --
 * the two most common, most valuable cases -- are ported in full.
 */
object HintRationaleTemplates {

    private const val GENERIC = "A solid move that improves the position."

    private val pieceNames = mapOf(
        PieceType.PAWN to "pawn", PieceType.KNIGHT to "knight", PieceType.BISHOP to "bishop",
        PieceType.ROOK to "rook", PieceType.QUEEN to "queen", PieceType.KING to "king",
    )

    /** [mateIn]: forced-mate distance for the side to move, if already known
     *  from the engine's own eval (positive only -- a mate suffered is not a
     *  reason to recommend the move). */
    fun rationale(boardBefore: Board, move: Move, mateIn: Int? = null): String {
        if (mateIn != null && mateIn > 0) {
            return if (mateIn == 1) "Delivers checkmate." else "Sets up a forced mate in $mateIn."
        }
        val capturedType = boardBefore.pieceAt(move.to)?.type
        if (capturedType != null) {
            val name = pieceNames[capturedType] ?: "piece"
            return "Wins a $name."
        }
        return GENERIC
    }
}
