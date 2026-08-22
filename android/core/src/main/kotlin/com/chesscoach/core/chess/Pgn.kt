package com.chesscoach.core.chess

/** Minimal PGN support: mainline-only movetext parsing (comments, NAGs, and
 *  variations are discarded), sufficient for importing a finished game to review. */
object Pgn {

    private val RESULT_TOKENS = setOf("1-0", "0-1", "1/2-1/2", "*")

    /** The starting FEN declared by a `[FEN "..."]` header, or the standard starting
     *  position if absent. */
    fun startingFen(pgn: String): String {
        val match = Regex("""\[FEN\s+"([^"]*)"\]""").find(pgn)
        return match?.groupValues?.get(1) ?: Board.STARTING_FEN
    }

    /** The mainline SAN move list, in play order. Comments `{...}`, NAGs (`$n`), and
     *  parenthesized variations are stripped; move numbers and result markers too. */
    fun mainlineSan(pgn: String): List<String> {
        var text = pgn
        // Drop header lines like [Event "..."].
        text = text.lines().filterNot { it.trim().startsWith("[") }.joinToString(" ")
        // Drop comments (non-nested is sufficient for typical exports).
        text = Regex("""\{[^}]*\}""").replace(text, " ")
        // Drop nested variations: repeatedly strip innermost (...) until none remain.
        var previous: String
        do {
            previous = text
            text = Regex("""\([^()]*\)""").replace(text, " ")
        } while (text != previous)
        // Drop NAGs like $1.
        text = Regex("""\$\d+""").replace(text, " ")

        return text.split(Regex("\\s+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .filter { it !in RESULT_TOKENS }
            .filterNot { Regex("""^\d+\.+$""").matches(it) }
            .map { Regex("""^\d+\.+""").replace(it, "") }
            .filter { it.isNotEmpty() }
    }

    /** The FEN after every mainline move, in play order (starting position is not
     *  included). Stops early if a move fails to parse/apply. */
    fun fens(pgn: String): List<String> {
        var board = Board.fromFen(startingFen(pgn)) ?: return emptyList()
        val out = mutableListOf<String>()
        for (san in mainlineSan(pgn)) {
            val move = San.parse(board, san) ?: break
            board = board.applyMove(move)
            out.add(board.fen())
        }
        return out
    }

    /** The FEN of the final mainline position, or the starting position for a
     *  moveless game. Null only if the PGN's starting FEN itself is invalid. */
    fun finalFen(pgn: String): String? {
        val fens = fens(pgn)
        if (fens.isNotEmpty()) return fens.last()
        return Board.fromFen(startingFen(pgn))?.fen()
    }
}
