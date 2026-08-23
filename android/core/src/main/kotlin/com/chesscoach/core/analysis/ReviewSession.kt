package com.chesscoach.core.analysis

/** One node (position) in a game's review timeline -- port of iOS `TimelineNode`.
 *  Non-final nodes carry their outgoing move plus (for the reviewed side's
 *  moves) its classification and mistake-list link. */
data class TimelineNode(
    val node: Int,
    val fen: String,
    val winWhite: Double,
    val color: String,
    val moveNumber: Int,
    val ply: Int? = null,
    val moveSan: String? = null,
    val moveUci: String? = null,
    val bestUci: String? = null,
    val bestSan: String? = null,
    val isMyMove: Boolean? = null,
    val classification: String? = null,
    val mistakeIndex: Int? = null,
)

/** One of the reviewed side's moves, graded -- port of iOS `MoveReview` (trimmed
 *  to the fields this build's review UI actually reads; no coach/clock fields). */
data class MoveReview(
    val ply: Int,
    val moveNumber: Int,
    val color: String,
    val moveSan: String,
    val moveUci: String,
    val fenBefore: String,
    val fenAfter: String,
    val winBefore: Double,
    val winAfter: Double,
    val winSwing: Double,
    val classification: String,
    val bestMoveSan: String,
    val accuracy: Double,
    val comment: String,
)

/** Everything about one analysed/played game -- port of iOS `ReviewSession`,
 *  trimmed to what this build's review UI needs (no coach summary, no Elo/
 *  threshold metadata, no explore-fen scrubbing state). */
data class ReviewSession(
    val pgn: String,
    val player: String,
    val headers: Map<String, String>,
    val result: String,
    val accuracyWhite: Double,
    val accuracyBlack: Double,
    val allMoves: List<MoveReview>,
    val mistakes: List<MoveReview>,
    val timeline: List<TimelineNode>,
)
