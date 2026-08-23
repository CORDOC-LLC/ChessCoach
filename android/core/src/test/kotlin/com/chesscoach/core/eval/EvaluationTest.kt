package com.chesscoach.core.eval

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Transliterated from `Tests/GemmaChessCoreTests/EvaluationTests.swift` --
 *  same cases, same expected values, so a given eval reads identically on
 *  both platforms. */
class EvaluationTest {

    @Test
    fun `winPercent of zero is fifty`() {
        assertTrue(abs(Evaluation.winPercent(0.0) - 50.0) < 1e-9)
    }

    @Test
    fun `winPercent clamps and stays symmetric about 50`() {
        val hi = Evaluation.winPercent(2000.0) // beyond clamp
        val lo = Evaluation.winPercent(-2000.0)
        assertTrue(hi > 95.0 && hi <= 100.0)
        assertTrue(lo < 5.0 && lo >= 0.0)
        assertTrue(abs((hi - 50.0) - (50.0 - lo)) < 1e-9)
    }

    @Test
    fun `winPercent saturates beyond the clamp`() {
        assertEquals(Evaluation.winPercent(1000.0), Evaluation.winPercent(5000.0))
        assertEquals(Evaluation.winPercent(-1000.0), Evaluation.winPercent(-9999.0))
    }

    @Test
    fun `winPercent is monotonic in cp`() {
        assertTrue(Evaluation.winPercent(-100.0) < Evaluation.winPercent(0.0))
        assertTrue(Evaluation.winPercent(0.0) < Evaluation.winPercent(100.0))
        assertTrue(Evaluation.winPercent(100.0) < Evaluation.winPercent(300.0))
    }

    @Test
    fun `winPercentFromScore handles mate and null`() {
        assertEquals(100.0, Evaluation.winPercentFromScore(cp = null, mate = 3))
        assertEquals(0.0, Evaluation.winPercentFromScore(cp = null, mate = -2))
        assertEquals(50.0, Evaluation.winPercentFromScore(cp = null, mate = null))
        assertTrue(abs(Evaluation.winPercentFromScore(cp = 0, mate = null) - 50.0) < 1e-9)
    }

    @Test
    fun `moveAccuracy of no drop is 100`() {
        val acc = Evaluation.moveAccuracy(winBefore = 50.0, winAfter = 50.0)
        assertTrue(abs(acc - 100.0) < 0.001 && acc <= 100.0)
    }

    @Test
    fun `moveAccuracy decreases as the drop grows`() {
        val a = Evaluation.moveAccuracy(winBefore = 100.0, winAfter = 95.0) // drop 5
        val b = Evaluation.moveAccuracy(winBefore = 100.0, winAfter = 80.0) // drop 20
        assertTrue(a > b)
    }

    @Test
    fun `aggregateAccuracy of empty list is 100`() {
        assertEquals(100.0, Evaluation.aggregateAccuracy(emptyList()))
    }

    @Test
    fun `aggregateAccuracy averages the given accuracies`() {
        assertEquals(75.0, Evaluation.aggregateAccuracy(listOf(50.0, 100.0)))
    }
}
