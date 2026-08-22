package com.chesscoach.core.chess

/**
 * Pure, deterministic chess helpers on top of [Board]/[MoveGen]/[San]. Everything
 * here is engine-free and side-effect-free: parse inputs, do the work, return a
 * value (or null on bad input). Mirrors the iOS `ChessLogic` facade so the two apps
 * share the same behavioral contract even though the implementations differ.
 */
object ChessLogic {

    fun isValidFEN(fen: String): Boolean = Board.fromFen(fen) != null

    fun normalizedFEN(fen: String): String? = Board.fromFen(fen)?.fen()

    /** The EPD key (first four FEN fields) -- two positions differing only in move
     *  counters collapse to the same key. */
    fun epd(fen: String): String? {
        val fields = fen.trim().split(Regex("\\s+"))
        if (fields.size < 4) return null
        return fields.take(4).joinToString(" ")
    }

    fun sideToMove(fen: String): Color? = Board.fromFen(fen)?.sideToMove

    fun status(fen: String): GameStatus? = Board.fromFen(fen)?.let { GameStatus.of(it) }

    fun isCheck(fen: String): Boolean = status(fen) == GameStatus.CHECK || status(fen) == GameStatus.CHECKMATE

    /** Legal destinations for every piece of the side to move, keyed by origin square. */
    fun legalDestinations(fen: String): Map<Square, List<Square>> {
        val board = Board.fromFen(fen) ?: return emptyMap()
        return MoveGen.legalMoves(board).groupBy({ it.from }, { it.to })
    }

    fun uciFromSan(san: String, fen: String): String? {
        val board = Board.fromFen(fen) ?: return null
        return San.parse(board, san)?.uci
    }

    fun sanFromUci(uci: String, fen: String): String? {
        val board = Board.fromFen(fen) ?: return null
        val move = parseUci(board, uci) ?: return null
        return San.of(board, move)
    }

    /** Applies a move (SAN or UCI/LAN) to `fen`, returning the resulting FEN, or null
     *  if the FEN or move is invalid/illegal. */
    fun fenAfterMove(move: String, fen: String): String? {
        val board = Board.fromFen(fen) ?: return null
        val resolved = San.parse(board, move) ?: parseUci(board, move) ?: return null
        return board.applyMove(resolved).fen()
    }

    /** Replays a UCI/LAN principal variation onto `fen`, collecting SAN for each move
     *  (with check/mate markers). Stops early at the first illegal move. */
    fun pvToSan(uciMoves: List<String>, fen: String, maxMoves: Int = 12): List<String> {
        var board = Board.fromFen(fen) ?: return emptyList()
        val sans = mutableListOf<String>()
        for (uci in uciMoves.take(maxMoves)) {
            val move = parseUci(board, uci) ?: break
            sans.add(San.of(board, move))
            board = board.applyMove(move)
        }
        return sans
    }

    /** Parses a UCI/LAN move string (e.g. "e2e4", "e7e8q") against `board`. */
    fun parseUci(board: Board, uci: String): Move? {
        if (uci.length !in 4..5) return null
        val from = Square.parse(uci.substring(0, 2)) ?: return null
        val to = Square.parse(uci.substring(2, 4)) ?: return null
        val promoChar = uci.getOrNull(4)
        return MoveGen.legalMoves(board, from).firstOrNull {
            it.to == to && (promoChar == null || it.promotion?.symbol?.lowercaseChar() == promoChar)
        }
    }
}
