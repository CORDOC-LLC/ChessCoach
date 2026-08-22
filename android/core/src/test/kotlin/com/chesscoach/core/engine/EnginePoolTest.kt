package com.chesscoach.core.engine

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.test.runTest
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Drives [EnginePool] against scripted UCI responses instead of a real Stockfish
 *  process -- exercises the response-parsing and caching logic without needing a
 *  compiled binary (which this sandbox cannot build; see android/README.md). */
private class FakeUciTransport(private val goResponses: MutableList<List<String>>) : UciTransport {
    override val lines: Channel<String> = Channel(Channel.UNLIMITED)
    val sent = mutableListOf<String>()

    override fun send(command: String) {
        sent.add(command)
        when {
            command == "uci" -> lines.trySend("uciok")
            command == "isready" -> lines.trySend("readyok")
            command.startsWith("go depth") -> {
                val script = if (goResponses.isNotEmpty()) goResponses.removeAt(0) else listOf("bestmove (none)")
                script.forEach { lines.trySend(it) }
            }
        }
    }

    override fun close() { lines.close() }
}

class EnginePoolTest {

    @Test
    fun analyseParsesMultiPvInfoAndCaches() = runTest {
        val goScript = listOf(
            "info depth 10 multipv 1 score cp 35 pv e2e4 e7e5",
            "info depth 10 multipv 2 score mate 3 pv d2d4 d7d5",
            "bestmove e2e4",
        )
        var callCount = 0
        val engine = EnginePool(
            binaryPath = "unused",
            transportFactory = { _ ->
                FakeUciTransport(mutableListOf(goScript)).also { callCount++ }
            },
        )

        val result = engine.analyse("startpos-fen", depth = 10, multipv = 2)
        assertEquals(2, result.lines.size)
        assertEquals(35, result.lines[0].cp)
        assertEquals(listOf("e2e4", "e7e5"), result.lines[0].pvUci)
        assertEquals(3, result.lines[1].mate)

        // Second call with identical key must hit the cache, not re-invoke the engine.
        val again = engine.analyse("startpos-fen", depth = 10, multipv = 2)
        assertEquals(result, again)
        assertEquals(1, callCount)
    }

    @Test
    fun playMoveReturnsBestMove() = runTest {
        val engine = EnginePool(
            binaryPath = "unused",
            transportFactory = { _ ->
                FakeUciTransport(mutableListOf(listOf("info depth 12 multipv 1 score cp 10 pv g1f3", "bestmove g1f3")))
            },
        )
        assertEquals("g1f3", engine.playMove("startpos-fen", depth = 12))
    }

    @Test
    fun playMoveReturnsNullOnNoLegalMove() = runTest {
        val engine = EnginePool(
            binaryPath = "unused",
            transportFactory = { _ -> FakeUciTransport(mutableListOf(listOf("bestmove (none)"))) },
        )
        assertNull(engine.playMove("terminal-fen", depth = 12))
    }

    @Test
    fun weightedPickSingleCandidateIsDeterministic() {
        val lines = listOf(EngineLineResult(cp = 20, mate = null, pvUci = listOf("e2e4")))
        assertEquals("e2e4", EnginePool.weightedPick(lines, skill = 0))
    }

    @Test
    fun weightedPickAlwaysReturnsARealCandidate() {
        val lines = listOf(
            EngineLineResult(20, null, listOf("e2e4")),
            EngineLineResult(15, null, listOf("d2d4")),
            EngineLineResult(10, null, listOf("g1f3")),
        )
        val candidates = lines.map { it.pvUci.first() }.toSet()
        val rng = Random(42)
        repeat(200) { skill ->
            val pick = EnginePool.weightedPick(lines, skill % 20, random = rng)
            assertNotNull(pick)
            assert(pick in candidates) { "picked $pick not in $candidates" }
        }
    }

    @Test
    fun weightedPickFavorsTopCandidateAsSkillApproachesThreshold() {
        val lines = listOf(
            EngineLineResult(20, null, listOf("best")),
            EngineLineResult(15, null, listOf("second")),
            EngineLineResult(10, null, listOf("third")),
            EngineLineResult(5, null, listOf("fourth")),
        )
        val rng = Random(7)
        var bestCount = 0
        val trials = 2000
        repeat(trials) {
            if (EnginePool.weightedPick(lines, skill = EnginePool.LOW_SKILL_THRESHOLD - 1, random = rng) == "best") bestCount++
        }
        // Near the top of the low-skill band the top candidate should dominate heavily
        // (exact probability here is ~80%; 70% leaves headroom against sampling noise).
        assert(bestCount > trials * 0.7) { "expected 'best' to dominate, got $bestCount/$trials" }
    }
}
