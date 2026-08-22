package com.chesscoach.core.chess

/** Pseudo-legal and legal move generation, plus attack queries. */
object MoveGen {

    private val KNIGHT_DELTAS = listOf(1 to 2, 2 to 1, 2 to -1, 1 to -2, -1 to -2, -2 to -1, -2 to 1, -1 to 2)
    private val KING_DELTAS = listOf(1 to 0, 1 to 1, 0 to 1, -1 to 1, -1 to 0, -1 to -1, 0 to -1, 1 to -1)
    private val BISHOP_DIRS = listOf(1 to 1, 1 to -1, -1 to 1, -1 to -1)
    private val ROOK_DIRS = listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)
    private val QUEEN_DIRS = BISHOP_DIRS + ROOK_DIRS
    private val PROMOTION_PIECES = listOf(PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT)

    fun isInCheck(board: Board, color: Color): Boolean {
        val king = board.kingSquare(color) ?: return false
        return isSquareAttacked(board, king, color.opposite())
    }

    fun isSquareAttacked(board: Board, square: Square, byColor: Color): Boolean {
        // Pawns
        val pawnRankDelta = if (byColor == Color.WHITE) -1 else 1
        for (df in intArrayOf(-1, 1)) {
            val s = Square.ofOrNull(square.file + df, square.rank + pawnRankDelta) ?: continue
            val p = board.pieceAt(s)
            if (p != null && p.color == byColor && p.type == PieceType.PAWN) return true
        }
        // Knights
        for ((df, dr) in KNIGHT_DELTAS) {
            val s = Square.ofOrNull(square.file + df, square.rank + dr) ?: continue
            val p = board.pieceAt(s)
            if (p != null && p.color == byColor && p.type == PieceType.KNIGHT) return true
        }
        // King
        for ((df, dr) in KING_DELTAS) {
            val s = Square.ofOrNull(square.file + df, square.rank + dr) ?: continue
            val p = board.pieceAt(s)
            if (p != null && p.color == byColor && p.type == PieceType.KING) return true
        }
        // Sliding: bishop/queen diagonals
        for ((df, dr) in BISHOP_DIRS) {
            var f = square.file + df; var r = square.rank + dr
            while (true) {
                val s = Square.ofOrNull(f, r) ?: break
                val p = board.pieceAt(s)
                if (p != null) {
                    if (p.color == byColor && (p.type == PieceType.BISHOP || p.type == PieceType.QUEEN)) return true
                    break
                }
                f += df; r += dr
            }
        }
        // Sliding: rook/queen orthogonals
        for ((df, dr) in ROOK_DIRS) {
            var f = square.file + df; var r = square.rank + dr
            while (true) {
                val s = Square.ofOrNull(f, r) ?: break
                val p = board.pieceAt(s)
                if (p != null) {
                    if (p.color == byColor && (p.type == PieceType.ROOK || p.type == PieceType.QUEEN)) return true
                    break
                }
                f += df; r += dr
            }
        }
        return false
    }

    /** All legal moves for the side to move. */
    fun legalMoves(board: Board): List<Move> {
        val side = board.sideToMove
        return pseudoLegalMoves(board).filter { move ->
            val after = board.applyMove(move)
            !isInCheck(after, side)
        }
    }

    fun legalMoves(board: Board, from: Square): List<Move> =
        legalMoves(board).filter { it.from == from }

    /** All pseudo-legal moves for the side to move (does not filter out moves that
     *  leave the mover's own king in check). */
    fun pseudoLegalMoves(board: Board): List<Move> {
        val side = board.sideToMove
        val moves = mutableListOf<Move>()
        for ((square, piece) in board.allPieces()) {
            if (piece.color != side) continue
            when (piece.type) {
                PieceType.PAWN -> generatePawnMoves(board, square, piece, moves)
                PieceType.KNIGHT -> generateStepMoves(board, square, piece, KNIGHT_DELTAS, moves)
                PieceType.KING -> {
                    generateStepMoves(board, square, piece, KING_DELTAS, moves)
                    generateCastleMoves(board, square, piece, moves)
                }
                PieceType.BISHOP -> generateSlideMoves(board, square, piece, BISHOP_DIRS, moves)
                PieceType.ROOK -> generateSlideMoves(board, square, piece, ROOK_DIRS, moves)
                PieceType.QUEEN -> generateSlideMoves(board, square, piece, QUEEN_DIRS, moves)
            }
        }
        return moves
    }

    private fun generateStepMoves(
        board: Board, from: Square, piece: Piece, deltas: List<Pair<Int, Int>>, out: MutableList<Move>
    ) {
        for ((df, dr) in deltas) {
            val to = Square.ofOrNull(from.file + df, from.rank + dr) ?: continue
            val target = board.pieceAt(to)
            if (target == null) {
                out.add(Move(from, to, piece))
            } else if (target.color != piece.color) {
                out.add(Move(from, to, piece, MoveFlag.CAPTURE, captured = target))
            }
        }
    }

    private fun generateSlideMoves(
        board: Board, from: Square, piece: Piece, dirs: List<Pair<Int, Int>>, out: MutableList<Move>
    ) {
        for ((df, dr) in dirs) {
            var f = from.file + df; var r = from.rank + dr
            while (true) {
                val to = Square.ofOrNull(f, r) ?: break
                val target = board.pieceAt(to)
                if (target == null) {
                    out.add(Move(from, to, piece))
                } else {
                    if (target.color != piece.color) out.add(Move(from, to, piece, MoveFlag.CAPTURE, captured = target))
                    break
                }
                f += df; r += dr
            }
        }
    }

    private fun generatePawnMoves(board: Board, from: Square, piece: Piece, out: MutableList<Move>) {
        val forward = if (piece.color == Color.WHITE) 1 else -1
        val startRank = if (piece.color == Color.WHITE) 1 else 6
        val promotionRank = if (piece.color == Color.WHITE) 7 else 0

        fun addForwardOrPromotion(to: Square, flag: MoveFlag) {
            if (to.rank == promotionRank) {
                for (promo in PROMOTION_PIECES) out.add(Move(from, to, piece, MoveFlag.PROMOTION, promo))
            } else {
                out.add(Move(from, to, piece, flag))
            }
        }

        // Single push
        val oneStep = Square.ofOrNull(from.file, from.rank + forward)
        if (oneStep != null && board.pieceAt(oneStep) == null) {
            addForwardOrPromotion(oneStep, MoveFlag.NORMAL)
            // Double push
            if (from.rank == startRank) {
                val twoStep = Square.ofOrNull(from.file, from.rank + 2 * forward)
                if (twoStep != null && board.pieceAt(twoStep) == null) {
                    out.add(Move(from, twoStep, piece, MoveFlag.DOUBLE_PAWN))
                }
            }
        }
        // Captures
        for (df in intArrayOf(-1, 1)) {
            val to = Square.ofOrNull(from.file + df, from.rank + forward) ?: continue
            val target = board.pieceAt(to)
            if (target != null && target.color != piece.color) {
                addForwardOrPromotion(to, MoveFlag.CAPTURE)
            } else if (target == null && to == board.enPassantTarget) {
                out.add(Move(from, to, piece, MoveFlag.EN_PASSANT, captured = Piece(piece.color.opposite(), PieceType.PAWN)))
            }
        }
    }

    private fun generateCastleMoves(board: Board, from: Square, piece: Piece, out: MutableList<Move>) {
        val color = piece.color
        val rank = if (color == Color.WHITE) 0 else 7
        if (from != Square.of(4, rank)) return
        if (isInCheck(board, color)) return
        val opponent = color.opposite()
        val kingside = if (color == Color.WHITE) board.castlingRights.whiteKingside else board.castlingRights.blackKingside
        val queenside = if (color == Color.WHITE) board.castlingRights.whiteQueenside else board.castlingRights.blackQueenside

        if (kingside) {
            val f1 = Square.of(5, rank); val f2 = Square.of(6, rank)
            if (board.pieceAt(f1) == null && board.pieceAt(f2) == null &&
                !isSquareAttacked(board, f1, opponent) && !isSquareAttacked(board, f2, opponent)
            ) {
                out.add(Move(from, f2, piece, MoveFlag.CASTLE_KINGSIDE))
            }
        }
        if (queenside) {
            val d1 = Square.of(3, rank); val d2 = Square.of(2, rank); val d3 = Square.of(1, rank)
            if (board.pieceAt(d1) == null && board.pieceAt(d2) == null && board.pieceAt(d3) == null &&
                !isSquareAttacked(board, d1, opponent) && !isSquareAttacked(board, d2, opponent)
            ) {
                out.add(Move(from, d2, piece, MoveFlag.CASTLE_QUEENSIDE))
            }
        }
    }
}
