package com.chesscoach.core.eval

import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

/**
 * Centipawn <-> win% conversion and accuracy scoring -- a direct Kotlin port
 * of `Sources/GemmaChessCore/Evaluation/Evaluation.swift`'s `winPercent`/
 * `moveAccuracy`/`aggregateAccuracy`, same constants, same formulas, so a
 * given eval reads identically on both platforms.
 */
object Evaluation {
    private const val WIN_K = 0.003_682_08
    private const val CP_CLAMP = 1000.0

    /** Centipawn score (side-to-move relative) -> win% in [0, 100]. cp == 0 -> 50. */
    fun winPercent(cp: Double): Double {
        val c = max(-CP_CLAMP, min(CP_CLAMP, cp))
        return 50.0 + 50.0 * (2.0 / (1.0 + exp(-WIN_K * c)) - 1.0)
    }

    /** Win% from either a centipawn value or mate-in-N -- exactly one is meaningful. */
    fun winPercentFromScore(cp: Int?, mate: Int?): Double {
        if (mate != null) return if (mate > 0) 100.0 else 0.0
        if (cp == null) return 50.0
        return winPercent(cp.toDouble())
    }

    /** Per-move accuracy% in [0, 100] from the win% drop (Lichess-style). */
    fun moveAccuracy(winBefore: Double, winAfter: Double): Double {
        val drop = max(0.0, winBefore - winAfter)
        val acc = 103.1668 * exp(-0.04354 * drop) - 3.1669
        return max(0.0, min(100.0, acc))
    }

    /** Aggregate per-move accuracies into one per-side accuracy%. Empty -> 100. */
    fun aggregateAccuracy(accuracies: List<Double>): Double {
        if (accuracies.isEmpty()) return 100.0
        return accuracies.sum() / accuracies.size
    }

    /** Human-readable eval from the side-to-move perspective, e.g. "+1.23",
     *  "-0.45", "#3", "#-3" -- same format as iOS's `EngineLine.evalStr`. */
    fun evalText(cp: Int?, mate: Int?): String {
        if (mate != null) return if (mate > 0) "#$mate" else "#-${-mate}"
        val pawns = (cp ?: 0) / 100.0
        return (if (pawns >= 0) "+" else "") + "%.2f".format(pawns)
    }
}
