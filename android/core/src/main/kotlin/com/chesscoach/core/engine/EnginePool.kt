package com.chesscoach.core.engine

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

/**
 * Process-wide Stockfish engine, serialized and cached. A Kotlin port of the iOS
 * `EnginePool` actor: same caching semantics, same weighted-sampling "human-like"
 * opponent behavior, driven over UCI against a native Stockfish binary instead of
 * ChessKitEngine.
 */
class EnginePool(
    private val binaryPath: String,
    private val engineThreads: Int = 2,
    private val hashMb: Int = 64,
    private val transportFactory: (CoroutineScope) -> UciTransport = { scope -> ProcessUciTransport(binaryPath, scope) },
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var transport: UciTransport? = null
    private var started = false
    private var currentMultipv = 0
    private val cache = LinkedHashMap<CacheKey, AnalysisResult>()
    private val gate = Mutex()

    private data class CacheKey(val fen: String, val depth: Int, val multipv: Int)

    companion object {
        /** Below this Stockfish "Skill Level" (0-20), [humanLikeMove] samples among the
         *  top candidates rather than always returning the best move. */
        const val LOW_SKILL_THRESHOLD = 10

        /** Number of top candidate lines requested for weighted sampling. */
        const val HUMAN_LIKE_MULTIPV = 4

        /** Weighted random pick of a first move (UCI) among candidate lines, favoring
         *  earlier (better-ranked) lines more strongly as `skill` approaches
         *  [lowSkillThreshold]. Exposed for direct unit testing without spinning up the
         *  engine. */
        fun weightedPick(
            lines: List<EngineLineResult>,
            skill: Int,
            lowSkillThreshold: Int = LOW_SKILL_THRESHOLD,
            random: Random = Random.Default,
        ): String? {
            val candidates = lines.mapNotNull { it.pvUci.firstOrNull() }
            if (candidates.isEmpty()) return null
            if (candidates.size == 1) return candidates[0]

            val band = max(1, lowSkillThreshold - 1)
            val t = max(0, min(lowSkillThreshold - 1, skill)).toDouble() / band
            val flattestDecay = 0.85
            val sharpestDecay = 0.20
            val decay = flattestDecay + (sharpestDecay - flattestDecay) * t

            val weights = DoubleArray(candidates.size) { i -> decay.pow(i) }
            val total = weights.sum()
            if (total <= 0) return candidates[0]

            val r = random.nextDouble() * total
            var running = 0.0
            for (i in candidates.indices) {
                running += weights[i]
                if (r < running) return candidates[i]
            }
            return candidates.last()
        }
    }

    /** Analyse a FEN at fixed depth. Cached and reproducible. */
    suspend fun analyse(fen: String, depth: Int, multipv: Int = 1): AnalysisResult {
        val mpv = max(1, multipv)
        val key = CacheKey(fen, depth, mpv)
        cache[key]?.let { return it }

        return gate.withLock {
            cache[key]?.let { return@withLock it }
            ensureStarted()
            val result = runQuery(fen, depth, mpv)
            cache[key] = result
            result
        }
    }

    /** Pick an OPPONENT reply via weighted random sampling over the engine's own top
     *  candidate moves, for skills below [LOW_SKILL_THRESHOLD]. Always a real
     *  engine-approved candidate at the requested depth. Null if there is no legal
     *  move (game over). */
    suspend fun humanLikeMove(fen: String, depth: Int = 12, skill: Int, multipv: Int = HUMAN_LIKE_MULTIPV): String? {
        val clampedSkill = max(0, min(20, skill))
        val result = analyse(fen, depth, max(1, multipv))
        return weightedPick(result.lines, clampedSkill)
    }

    /** Pick a move for an OPPONENT to play (used by Play mode). Optional [skill]
     *  (0-20) makes it beatable; the engine is reset to full strength afterwards. Not
     *  cached. Null if there is no legal move. */
    suspend fun playMove(fen: String, depth: Int = 12, skill: Int? = null): String? = gate.withLock {
        ensureStarted()
        val t = transport ?: throw EngineException("Engine not started")

        if (skill != null) t.send("setoption name Skill Level value ${max(0, min(20, skill))}")
        if (currentMultipv != 1) {
            t.send("setoption name MultiPV value 1")
            currentMultipv = 1
        }
        t.send("position fen $fen")
        val bestMove = goAndCollect(t, depth).second
        if (skill != null) t.send("setoption name Skill Level value 20")
        if (bestMove == null || bestMove == "(none)" || bestMove.length < 4) null else bestMove
    }

    /** Quit the engine and drop cached evals. */
    suspend fun shutdown() = gate.withLock {
        transport?.close()
        transport = null
        started = false
        currentMultipv = 0
        cache.clear()
    }

    // MARK: private

    private suspend fun runQuery(fen: String, depth: Int, multipv: Int): AnalysisResult {
        val t = transport ?: throw EngineException("Engine not started")
        if (multipv != currentMultipv) {
            t.send("setoption name MultiPV value $multipv")
            currentMultipv = multipv
        }
        t.send("position fen $fen")
        val (infos, _) = goAndCollect(t, depth)

        val lines = (1..multipv).mapNotNull { infos[it] }
        if (lines.isEmpty()) throw EngineException("Engine returned no lines for $fen")
        return AnalysisResult(fen, depth, lines)
    }

    /** Sends `go depth N` and reads responses until `bestmove`, accumulating the
     *  latest `info` line per multipv index. Caller must hold [gate]. */
    private suspend fun goAndCollect(t: UciTransport, depth: Int): Pair<Map<Int, EngineLineResult>, String?> {
        t.send("go depth $depth")
        val infos = mutableMapOf<Int, EngineLineResult>()
        var bestMove: String? = null
        try {
            for (line in t.lines) {
                if (line.startsWith("info ")) {
                    parseInfo(line)?.let { (mpv, result) -> infos[mpv] = result }
                } else if (line.startsWith("bestmove")) {
                    bestMove = line.removePrefix("bestmove").trim().substringBefore(' ')
                    break
                }
            }
        } catch (_: ClosedReceiveChannelException) {
            // Engine process died mid-search; report what we collected.
        }
        return infos to bestMove
    }

    private fun parseInfo(line: String): Pair<Int, EngineLineResult>? {
        val tokens = line.split(" ")
        var multipv: Int? = null
        var cp: Int? = null
        var mate: Int? = null
        var isBound = false
        var pvStart = -1
        var i = 0
        while (i < tokens.size) {
            when (tokens[i]) {
                "multipv" -> { multipv = tokens.getOrNull(i + 1)?.toIntOrNull(); i += 2 }
                "score" -> {
                    val kind = tokens.getOrNull(i + 1)
                    val value = tokens.getOrNull(i + 2)?.toIntOrNull()
                    when (kind) {
                        "cp" -> cp = value
                        "mate" -> mate = value
                    }
                    i += 3
                }
                "lowerbound", "upperbound" -> { isBound = true; i += 1 }
                "pv" -> { pvStart = i + 1; i = tokens.size }
                else -> i += 1
            }
        }
        if (multipv == null || isBound || pvStart < 0 || pvStart >= tokens.size) return null
        val pv = tokens.subList(pvStart, tokens.size)
        if (pv.isEmpty() || (cp == null && mate == null)) return null
        return multipv to EngineLineResult(cp, mate, pv)
    }

    private suspend fun ensureStarted() {
        if (started) return
        val t = transportFactory(scope)
        transport = t
        currentMultipv = 1

        t.send("uci")
        waitFor(t, "uciok")

        t.send("setoption name Threads value $engineThreads")
        t.send("setoption name Hash value $hashMb")
        t.send("setoption name MultiPV value 1")

        t.send("isready")
        waitFor(t, "readyok")
        started = true
    }

    private suspend fun waitFor(t: UciTransport, token: String) {
        try {
            for (line in t.lines) {
                if (line.trim() == token) return
            }
        } catch (_: ClosedReceiveChannelException) {
            throw EngineException("Engine process closed before sending '$token'")
        }
        throw EngineException("Engine process closed before sending '$token'")
    }
}
