package com.chesscoach.core.chess

enum class Color {
    WHITE, BLACK;

    fun opposite(): Color = if (this == WHITE) BLACK else WHITE

    companion object {
        fun fromChar(c: Char): Color = if (c.isUpperCase()) WHITE else BLACK
    }
}

enum class PieceType(val symbol: Char) {
    PAWN('P'), KNIGHT('N'), BISHOP('B'), ROOK('R'), QUEEN('Q'), KING('K');

    companion object {
        fun fromSymbol(c: Char): PieceType = when (c.uppercaseChar()) {
            'P' -> PAWN
            'N' -> KNIGHT
            'B' -> BISHOP
            'R' -> ROOK
            'Q' -> QUEEN
            'K' -> KING
            else -> throw IllegalArgumentException("Unknown piece symbol '$c'")
        }
    }
}

data class Piece(val color: Color, val type: PieceType) {
    /** FEN/SAN letter: uppercase for white, lowercase for black. */
    val fenChar: Char
        get() = if (color == Color.WHITE) type.symbol else type.symbol.lowercaseChar()

    companion object {
        fun fromFenChar(c: Char): Piece = Piece(Color.fromChar(c), PieceType.fromSymbol(c))
    }
}
