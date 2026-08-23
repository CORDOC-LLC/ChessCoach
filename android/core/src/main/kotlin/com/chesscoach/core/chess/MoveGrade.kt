package com.chesscoach.core.chess

/** Engine-only move quality tiers, derived purely from centipawn loss (no LLM
 *  prose -- this build offers the review/engine tier, not the coach). Thresholds
 *  are the common lichess-style bands. */
enum class MoveGrade(val label: String) {
    BEST("Best"),
    EXCELLENT("Excellent"),
    GOOD("Good"),
    INACCURACY("Inaccuracy"),
    MISTAKE("Mistake"),
    BLUNDER("Blunder");

    companion object {
        /** [bestCpBeforeMove] and [actualCpAfterMove] are both from the mover's
         *  perspective (positive = good for the mover). [wasBestMove] short-circuits
         *  to [BEST] since engine ties/equal-eval alternatives shouldn't read as
         *  merely "Excellent". */
        fun classify(bestCpBeforeMove: Double, actualCpAfterMove: Double, wasBestMove: Boolean): MoveGrade {
            if (wasBestMove) return BEST
            val loss = (bestCpBeforeMove - actualCpAfterMove).coerceAtLeast(0.0)
            return when {
                loss < 10 -> EXCELLENT
                loss < 30 -> GOOD
                loss < 80 -> INACCURACY
                loss < 200 -> MISTAKE
                else -> BLUNDER
            }
        }
    }
}
