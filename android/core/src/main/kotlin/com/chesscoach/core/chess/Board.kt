package com.chesscoach.core.chess

data class CastlingRights(
    val whiteKingside: Boolean = true,
    val whiteQueenside: Boolean = true,
    val blackKingside: Boolean = true,
    val blackQueenside: Boolean = true,
) {
    val isEmpty: Boolean get() = !whiteKingside && !whiteQueenside && !blackKingside && !blackQueenside

    fun fenField(): String {
        if (isEmpty) return "-"
        val sb = StringBuilder()
        if (whiteKingside) sb.append('K')
        if (whiteQueenside) sb.append('Q')
        if (blackKingside) sb.append('k')
        if (blackQueenside) sb.append('q')
        return sb.toString()
    }

    companion object {
        fun parse(field: String): CastlingRights {
            if (field == "-") return CastlingRights(false, false, false, false)
            return CastlingRights(
                whiteKingside = field.contains('K'),
                whiteQueenside = field.contains('Q'),
                blackKingside = field.contains('k'),
                blackQueenside = field.contains('q'),
            )
        }
    }
}

/**
 * A chess position: piece placement plus the rest of FEN's fields. Immutable from
 * callers' perspective -- [applyMove] returns a new [Board] rather than mutating.
 */
class Board private constructor(
    private val squares: Array<Piece?>,
    val sideToMove: Color,
    val castlingRights: CastlingRights,
    val enPassantTarget: Square?,
    val halfmoveClock: Int,
    val fullmoveNumber: Int,
) {
    fun pieceAt(square: Square): Piece? = squares[square.index]

    fun allPieces(): List<Pair<Square, Piece>> =
        squares.indices.mapNotNull { i -> squares[i]?.let { Square(i) to it } }

    fun kingSquare(color: Color): Square? =
        squares.indices.firstOrNull { squares[it] == Piece(color, PieceType.KING) }?.let { Square(it) }

    /** Standard starting position. */
    fun fen(): String {
        val sb = StringBuilder()
        for (rank in 7 downTo 0) {
            var empty = 0
            for (file in 0..7) {
                val piece = squares[Square.of(file, rank).index]
                if (piece == null) {
                    empty++
                } else {
                    if (empty > 0) { sb.append(empty); empty = 0 }
                    sb.append(piece.fenChar)
                }
            }
            if (empty > 0) sb.append(empty)
            if (rank > 0) sb.append('/')
        }
        sb.append(' ').append(if (sideToMove == Color.WHITE) 'w' else 'b')
        sb.append(' ').append(castlingRights.fenField())
        sb.append(' ').append(enPassantTarget?.notation ?: "-")
        sb.append(' ').append(halfmoveClock)
        sb.append(' ').append(fullmoveNumber)
        return sb.toString()
    }

    /** Returns a new [Board] with [move] applied. Assumes [move] is legal. */
    fun applyMove(move: Move): Board {
        val newSquares = squares.copyOf()
        newSquares[move.from.index] = null
        val movedPiece = move.promotion?.let { Piece(move.piece.color, it) } ?: move.piece
        newSquares[move.to.index] = movedPiece

        if (move.flag == MoveFlag.EN_PASSANT) {
            val capturedRank = move.from.rank
            newSquares[Square.of(move.to.file, capturedRank).index] = null
        }
        if (move.flag == MoveFlag.CASTLE_KINGSIDE) {
            val rank = move.from.rank
            val rook = newSquares[Square.of(7, rank).index]
            newSquares[Square.of(7, rank).index] = null
            newSquares[Square.of(5, rank).index] = rook
        }
        if (move.flag == MoveFlag.CASTLE_QUEENSIDE) {
            val rank = move.from.rank
            val rook = newSquares[Square.of(0, rank).index]
            newSquares[Square.of(0, rank).index] = null
            newSquares[Square.of(3, rank).index] = rook
        }

        var rights = castlingRights
        if (move.piece.type == PieceType.KING) {
            rights = if (move.piece.color == Color.WHITE) rights.copy(whiteKingside = false, whiteQueenside = false)
            else rights.copy(blackKingside = false, blackQueenside = false)
        }
        fun clearRightsFor(square: Square, rights: CastlingRights): CastlingRights = when (square.index) {
            Square.of(0, 0).index -> rights.copy(whiteQueenside = false)
            Square.of(7, 0).index -> rights.copy(whiteKingside = false)
            Square.of(0, 7).index -> rights.copy(blackQueenside = false)
            Square.of(7, 7).index -> rights.copy(blackKingside = false)
            else -> rights
        }
        rights = clearRightsFor(move.from, rights)
        rights = clearRightsFor(move.to, rights)

        val newEnPassant = if (move.flag == MoveFlag.DOUBLE_PAWN) {
            Square.of(move.from.file, (move.from.rank + move.to.rank) / 2)
        } else null

        val resetClock = move.piece.type == PieceType.PAWN || move.isCapture
        val newHalfmove = if (resetClock) 0 else halfmoveClock + 1
        val newFullmove = if (sideToMove == Color.BLACK) fullmoveNumber + 1 else fullmoveNumber

        return Board(newSquares, sideToMove.opposite(), rights, newEnPassant, newHalfmove, newFullmove)
    }

    /** A copy of this board with only the side to move flipped and en passant cleared
     *  -- used for "is the side to move's king safe" queries without playing a move. */
    fun withSideToMoveFlipped(): Board =
        Board(squares.copyOf(), sideToMove.opposite(), castlingRights, null, halfmoveClock, fullmoveNumber)

    companion object {
        const val STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

        fun starting(): Board = fromFen(STARTING_FEN)!!

        fun fromFen(fen: String): Board? {
            val fields = fen.trim().split(Regex("\\s+"))
            if (fields.size < 4) return null
            val placement = fields[0]
            val ranks = placement.split("/")
            if (ranks.size != 8) return null

            val squares = arrayOfNulls<Piece?>(64)
            for ((i, rankStr) in ranks.withIndex()) {
                val rank = 7 - i
                var file = 0
                for (c in rankStr) {
                    if (c.isDigit()) {
                        file += c - '0'
                    } else {
                        if (file !in 0..7) return null
                        squares[Square.of(file, rank).index] = try {
                            Piece.fromFenChar(c)
                        } catch (e: IllegalArgumentException) {
                            return null
                        }
                        file++
                    }
                }
                if (file != 8) return null
            }

            val sideToMove = when (fields[1]) {
                "w" -> Color.WHITE
                "b" -> Color.BLACK
                else -> return null
            }
            val rights = CastlingRights.parse(fields[2])
            val enPassant = if (fields[3] == "-") null else Square.parse(fields[3])
            val halfmove = fields.getOrNull(4)?.toIntOrNull() ?: 0
            val fullmove = fields.getOrNull(5)?.toIntOrNull() ?: 1

            return Board(squares, sideToMove, rights, enPassant, halfmove, fullmove)
        }
    }
}
