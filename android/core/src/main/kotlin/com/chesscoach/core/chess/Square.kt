package com.chesscoach.core.chess

/**
 * A board square as an index 0..63: `index = rank * 8 + file`, `file` 0=a..7=h,
 * `rank` 0=rank1..7=rank8. Wraps an Int rather than allocating a class per square.
 */
@JvmInline
value class Square(val index: Int) {

    val file: Int get() = index and 7
    val rank: Int get() = index shr 3

    val isValid: Boolean get() = index in 0..63

    /** Algebraic notation, e.g. "e4". */
    val notation: String
        get() = "${('a' + file)}${rank + 1}"

    override fun toString(): String = notation

    companion object {
        /** Parses algebraic notation like "e4". Returns null if malformed. */
        fun parse(s: String): Square? {
            if (s.length != 2) return null
            val file = s[0].lowercaseChar() - 'a'
            val rank = s[1] - '1'
            if (file !in 0..7 || rank !in 0..7) return null
            return of(file, rank)
        }

        fun of(file: Int, rank: Int): Square = Square(rank * 8 + file)

        fun ofOrNull(file: Int, rank: Int): Square? =
            if (file in 0..7 && rank in 0..7) of(file, rank) else null
    }
}
