package com.chesscoach.core.engine

/** One principal variation from the engine, side-to-move relative. */
data class EngineLineResult(
    val cp: Int?,      // centipawns (null if mate)
    val mate: Int?,    // mate-in-N (null if cp)
    val pvUci: List<String>,
) {
    /** Signed centipawns (mate -> +-mateScoreCp). */
    fun signedCp(mateScoreCp: Int = 10_000): Double =
        if (mate != null) (if (mate > 0) mateScoreCp else -mateScoreCp).toDouble() else (cp ?: 0).toDouble()
}

/** Result of analysing one FEN. `lines[0]` is the best line. */
data class AnalysisResult(
    val fen: String,
    val depth: Int,
    val lines: List<EngineLineResult>,
) {
    val best: EngineLineResult get() = lines[0]
}

class EngineException(message: String) : Exception(message)
