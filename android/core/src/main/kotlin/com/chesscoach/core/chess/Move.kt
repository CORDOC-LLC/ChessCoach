package com.chesscoach.core.chess

enum class MoveFlag {
    NORMAL, CAPTURE, DOUBLE_PAWN, EN_PASSANT, CASTLE_KINGSIDE, CASTLE_QUEENSIDE, PROMOTION
}

data class Move(
    val from: Square,
    val to: Square,
    val piece: Piece,
    val flag: MoveFlag = MoveFlag.NORMAL,
    val promotion: PieceType? = null,
    val captured: Piece? = null,
) {
    val isCapture: Boolean get() = flag == MoveFlag.CAPTURE || flag == MoveFlag.EN_PASSANT
    val isCastle: Boolean get() = flag == MoveFlag.CASTLE_KINGSIDE || flag == MoveFlag.CASTLE_QUEENSIDE

    /** UCI/LAN notation, e.g. "e2e4", "e7e8q". */
    val uci: String
        get() = from.notation + to.notation + (promotion?.symbol?.lowercaseChar()?.toString() ?: "")
}
