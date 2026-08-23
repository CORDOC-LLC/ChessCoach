package com.chesscoach.core.chess

/** Standard piece values for the material-delta readout (king excluded -- it's
 *  never captured). */
private val PIECE_VALUE = mapOf(
    PieceType.PAWN to 1, PieceType.KNIGHT to 3, PieceType.BISHOP to 3,
    PieceType.ROOK to 5, PieceType.QUEEN to 9,
)

/** Standard starting count per piece type (one side). */
private val STARTING_COUNT = mapOf(
    PieceType.PAWN to 8, PieceType.KNIGHT to 2, PieceType.BISHOP to 2,
    PieceType.ROOK to 2, PieceType.QUEEN to 1,
)

/** Captured pieces (as FEN chars, sorted by value) and the net material delta
 *  for each side, derived by diffing the current board against the standard
 *  starting counts -- a direct port of the same computation
 *  `PlayViewModel.capturedMaterial` does on iOS. */
data class CapturedMaterial(
    val capturedByWhite: List<Char>, // black pieces White has captured
    val capturedByBlack: List<Char>, // white pieces Black has captured
    val delta: Int, // White's material advantage; negative favors Black
) {
    companion object {
        fun from(board: Board): CapturedMaterial {
            val onBoard = mutableMapOf<Piece, Int>()
            for ((_, piece) in board.allPieces()) {
                onBoard[piece] = (onBoard[piece] ?: 0) + 1
            }

            val capturedByWhite = mutableListOf<Char>() // black pieces missing
            val capturedByBlack = mutableListOf<Char>() // white pieces missing
            var delta = 0

            for ((type, startCount) in STARTING_COUNT) {
                val whiteMissing = startCount - (onBoard[Piece(Color.WHITE, type)] ?: 0)
                val blackMissing = startCount - (onBoard[Piece(Color.BLACK, type)] ?: 0)
                repeat(blackMissing) { capturedByWhite.add(Piece(Color.BLACK, type).fenChar) }
                repeat(whiteMissing) { capturedByBlack.add(Piece(Color.WHITE, type).fenChar) }
                val value = PIECE_VALUE.getValue(type)
                delta += (blackMissing - whiteMissing) * value
            }

            val order = listOf(PieceType.PAWN, PieceType.KNIGHT, PieceType.BISHOP, PieceType.ROOK, PieceType.QUEEN)
                .withIndex().associate { (i, t) -> t to i }
            fun sortKey(c: Char) = order.getValue(PieceType.fromSymbol(c))
            return CapturedMaterial(
                capturedByWhite = capturedByWhite.sortedBy(::sortKey),
                capturedByBlack = capturedByBlack.sortedBy(::sortKey),
                delta = delta,
            )
        }
    }
}
