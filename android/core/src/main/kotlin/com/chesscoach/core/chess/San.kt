package com.chesscoach.core.chess

/** Standard Algebraic Notation: converting a [Move] to/from SAN text. */
object San {

    /** SAN for `move`, including a trailing `+`/`#` if it checks/mates. `board` is the
     *  position *before* `move`. */
    fun of(board: Board, move: Move): String {
        val base = when (move.flag) {
            MoveFlag.CASTLE_KINGSIDE -> "O-O"
            MoveFlag.CASTLE_QUEENSIDE -> "O-O-O"
            else -> nonCastleSan(board, move)
        }
        val after = board.applyMove(move)
        val inCheck = MoveGen.isInCheck(after, after.sideToMove)
        val hasReply = MoveGen.legalMoves(after).isNotEmpty()
        return when {
            inCheck && !hasReply -> "$base#"
            inCheck -> "$base+"
            else -> base
        }
    }

    private fun nonCastleSan(board: Board, move: Move): String {
        val sb = StringBuilder()
        if (move.piece.type == PieceType.PAWN) {
            if (move.isCapture) sb.append(('a' + move.from.file)).append('x')
            sb.append(move.to.notation)
            if (move.flag == MoveFlag.PROMOTION) sb.append('=').append(move.promotion!!.symbol)
            return sb.toString()
        }

        sb.append(move.piece.type.symbol)
        sb.append(disambiguation(board, move))
        if (move.isCapture) sb.append('x')
        sb.append(move.to.notation)
        return sb.toString()
    }

    /** Minimal file/rank/square disambiguation among same-type pieces that could also
     *  reach `move.to`. */
    private fun disambiguation(board: Board, move: Move): String {
        val siblings = MoveGen.legalMoves(board).filter {
            it.to == move.to && it.piece.type == move.piece.type && it.from != move.from
        }
        if (siblings.isEmpty()) return ""
        val sameFile = siblings.any { it.from.file == move.from.file }
        val sameRank = siblings.any { it.from.rank == move.from.rank }
        return when {
            !sameFile -> ('a' + move.from.file).toString()
            !sameRank -> (move.from.rank + 1).toString()
            else -> move.from.notation
        }
    }

    /** Parses a SAN token (no move-number prefix, may include `+`/`#`) against the
     *  current position. Returns null if it doesn't match any legal move. */
    fun parse(board: Board, sanRaw: String): Move? {
        val san = sanRaw.trim().trimEnd('+', '#', '!', '?')
        if (san == "O-O" || san == "0-0") {
            return MoveGen.legalMoves(board).firstOrNull { it.flag == MoveFlag.CASTLE_KINGSIDE }
        }
        if (san == "O-O-O" || san == "0-0-0") {
            return MoveGen.legalMoves(board).firstOrNull { it.flag == MoveFlag.CASTLE_QUEENSIDE }
        }

        val promotion: PieceType? = san.substringAfter('=', "").firstOrNull()?.let { PieceType.fromSymbol(it) }
        val body = san.substringBefore('=')

        val pieceType = if (body[0].isUpperCase() && body[0] in "NBRQK") PieceType.fromSymbol(body[0]) else PieceType.PAWN
        val rest = if (pieceType == PieceType.PAWN) body else body.substring(1)
        val cleaned = rest.replace("x", "")
        if (cleaned.length < 2) return null
        val destStr = cleaned.takeLast(2)
        val dest = Square.parse(destStr) ?: return null
        val disambig = cleaned.dropLast(2)

        val candidates = MoveGen.legalMoves(board).filter {
            it.piece.type == pieceType && it.to == dest && it.promotion == promotion
        }
        if (candidates.size <= 1) return candidates.firstOrNull()

        return candidates.firstOrNull { move ->
            disambig.all { c ->
                when {
                    c.isDigit() -> move.from.rank == c - '1'
                    c.isLetter() -> move.from.file == c - 'a'
                    else -> true
                }
            }
        }
    }
}
