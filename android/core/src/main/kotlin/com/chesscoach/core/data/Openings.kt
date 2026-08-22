package com.chesscoach.core.data

import com.chesscoach.core.chess.Pgn

/**
 * Local ECO/opening-name lookup, keyed by placement + side-to-move + castling
 * rights (FEN's first three fields) so transpositions collapse to the same
 * position. Ported 1:1 from the iOS `Openings.swift` (itself ported from
 * `server/core/openings.py`). En passant and the move counters are deliberately
 * excluded from the key -- see that file's header for why en passant specifically,
 * not just move counters, must be dropped.
 */
class Openings private constructor(
    /** EPD-ish key (first 3 FEN fields) -> classified opening. */
    private val book: Map<String, Opening>,
    /** Every vendored ECO line, in its raw move-sequence form. */
    val lines: List<OpeningLine>,
) {
    data class Opening(val eco: String, val name: String)

    data class OpeningLine(val eco: String, val name: String, val sanMoves: List<String>) {
        /** Stable identity for persistence/list-diffing: ECO codes repeat across lines. */
        val id: String get() = "$eco|$name|${sanMoves.size}"

        /** Everything before the first ": " in [name], or the whole name. */
        val family: String get() = name.substringBefore(": ")

        /** The part after the family prefix, or null when this line IS the family's
         *  own main line. */
        val variationLabel: String? get() = if (name.contains(": ")) name.substringAfter(": ") else null
    }

    fun search(query: String): List<OpeningLine> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return lines
        return lines.filter {
            it.name.contains(trimmed, ignoreCase = true) || it.eco.contains(trimmed, ignoreCase = true)
        }
    }

    /** A random next move continuing some vendored line whose SAN prefix exactly
     *  matches [movesPlayed], or null once no line matches. */
    fun bookContinuation(movesPlayed: List<String>): String? {
        val candidates = lines.filter { it.sanMoves.size > movesPlayed.size && it.sanMoves.subList(0, movesPlayed.size) == movesPlayed }
        val pick = candidates.randomOrNull() ?: return null
        return pick.sanMoves[movesPlayed.size]
    }

    /** Deepest opening match across a game's positions in play order, or null. */
    fun classifyFromFens(fens: List<String>): Opening? {
        if (book.isEmpty()) return null
        var best: Opening? = null
        for (fen in fens) {
            val key = positionKey(fen) ?: continue
            book[key]?.let { best = it }
        }
        return best
    }

    /** Book hit for a single position, or null when it isn't a named line. */
    fun match(fen: String): Opening? {
        val key = positionKey(fen) ?: return null
        return book[key]
    }

    /** Deepest opening match for a full PGN string. */
    fun classifyFromPgn(pgn: String): Opening? = classifyFromFens(Pgn.fens(pgn))

    companion object {
        /** Parses the vendored TSV files' contents (one per `eco/{a..e}.tsv` file,
         *  header row `eco\tname\tpgn` included) into an [Openings] instance. */
        fun load(tsvContents: List<String>): Openings {
            val book = mutableMapOf<String, Opening>()
            val lines = mutableListOf<OpeningLine>()
            for (content in tsvContents) {
                for (rawLine in content.split("\n")) {
                    if (rawLine.isBlank()) continue
                    val columns = rawLine.split("\t")
                    if (columns.size != 3 || columns[0] == "eco") continue
                    val eco = columns[0]
                    val name = columns[1]
                    val movetext = columns[2]

                    val sanMoves = sanMovesFromMovetext(movetext)
                    if (sanMoves.isNotEmpty()) lines.add(OpeningLine(eco, name, sanMoves))

                    val fen = Pgn.finalFen(movetext) ?: continue
                    val key = positionKey(fen) ?: continue
                    book[key] = Opening(eco, name)
                }
            }
            return Openings(book, lines)
        }

        private fun positionKey(fen: String): String? {
            val fields = fen.trim().split(Regex("\\s+"))
            if (fields.size < 3) return null
            return fields.take(3).joinToString(" ")
        }

        private fun sanMovesFromMovetext(movetext: String): List<String> =
            movetext.split(" ")
                .filter { it.isNotEmpty() }
                .filterNot { token -> token.all { it.isDigit() || it == '.' } }
    }
}
