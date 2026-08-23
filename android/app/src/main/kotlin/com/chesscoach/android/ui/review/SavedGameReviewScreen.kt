package com.chesscoach.android.ui.review

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.board.EvalBarView
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedGlassCard
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.core.analysis.MoveReview
import com.chesscoach.core.chess.Square

private fun classificationColor(classification: String): Color = when (classification) {
    "best", "excellent", "good" -> ChessCoachTheme.accent
    "inaccuracy" -> ChessCoachTheme.accent2
    "mistake" -> Color(0xFFFF9800)
    "blunder" -> Color(0xFFE53935)
    else -> ChessCoachTheme.mutedText
}

@Composable
fun SavedGameReviewScreen(viewModel: SavedGameReviewViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "Review", onBack = onBack) {
        when {
            state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ChessCoachTheme.accent)
            }
            state.notReviewable -> Text(
                "This game doesn't have enough captured data to review yet -- it may " +
                    "predate this feature, or a move's grading raced an app close.",
                color = ChessCoachTheme.mutedText,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 24.dp),
            )
            else -> ReviewBody(state, viewModel)
        }
    }
}

@Composable
private fun ReviewBody(state: SavedGameReviewUiState, viewModel: SavedGameReviewViewModel) {
    val session = state.session ?: return
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            AccuracyChip("White", session.accuracyWhite)
            AccuracyChip("Black", session.accuracyBlack)
            Spacer(Modifier.weight(1f))
            if (session.mistakes.isNotEmpty()) {
                Text(
                    "${session.mistakes.size} mistake${if (session.mistakes.size == 1) "" else "s"}",
                    color = ChessCoachTheme.mutedText, fontSize = 12.sp,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
            }
        }

        Box(Modifier.fillMaxWidth().padding(top = 12.dp).aspectRatio(1f)) {
            val board = state.currentBoard
            if (board != null) {
                ChessBoardView(
                    board = board,
                    whiteAtBottom = state.orientationIsWhite,
                    lastMove = state.currentTimelineNode?.moveUci?.let { uci ->
                        if (uci.length < 4) null
                        else {
                            val from = Square.parse(uci.substring(0, 2))
                            val to = Square.parse(uci.substring(2, 4))
                            if (from != null && to != null) from to to else null
                        }
                    },
                    modifier = Modifier.padding(start = 22.dp),
                )
            }
            EvalBarView(
                winWhite = state.winWhiteCurrent,
                whiteAtBottom = state.orientationIsWhite,
                ringColor = ChessCoachTheme.accent2,
                modifier = Modifier.align(Alignment.CenterStart).fillMaxHeight(),
            )
        }

        Scrubber(state, viewModel)

        WinGraphView(
            values = state.winValues, currentIndex = state.currentNode,
            onScrub = viewModel::goto, modifier = Modifier.padding(top = 8.dp),
        )

        state.verdict?.let { VerdictBox(it) }

        if (session.mistakes.isNotEmpty()) MistakesList(session.mistakes, viewModel)

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun AccuracyChip(label: String, value: Double) {
    Column {
        Text("$label accuracy", color = ChessCoachTheme.mutedText, fontSize = 11.sp)
        Text("${value.toInt()}%", color = ChessCoachTheme.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun Scrubber(state: SavedGameReviewUiState, viewModel: SavedGameReviewViewModel) {
    Row(
        Modifier.fillMaxWidth().padding(top = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous",
            tint = if (state.currentNode > 0) ChessCoachTheme.text else ChessCoachTheme.faintText,
            modifier = Modifier.clickable(enabled = state.currentNode > 0, onClick = viewModel::prev),
        )
        Text(
            "Move ${state.currentNode} / ${(state.nodeCount - 1).coerceAtLeast(0)}",
            color = ChessCoachTheme.mutedText, fontSize = 13.sp,
            modifier = Modifier.width(120.dp),
        )
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next",
            tint = if (state.currentNode < state.nodeCount - 1) ChessCoachTheme.text else ChessCoachTheme.faintText,
            modifier = Modifier.clickable(enabled = state.currentNode < state.nodeCount - 1, onClick = viewModel::next),
        )
        Spacer(Modifier.weight(1f))
        Icon(
            Icons.Filled.SwapVert, contentDescription = "Flip board",
            tint = ChessCoachTheme.text.copy(alpha = 0.8f),
            modifier = Modifier.clickable(onClick = viewModel::flip),
        )
    }
}

@Composable
private fun VerdictBox(v: MoveReview) {
    ThemedGlassCard(cornerRadius = 12, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(v.moveSan, color = ChessCoachTheme.text, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(8.dp))
                Box(
                    Modifier
                        .background(classificationColor(v.classification).copy(alpha = 0.2f), RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 2.dp),
                ) {
                    Text(
                        v.classification.replaceFirstChar { it.uppercase() },
                        color = classificationColor(v.classification), fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    "win ${fmtPct(v.winBefore)}% → ${fmtPct(v.winAfter)}%",
                    color = ChessCoachTheme.mutedText, fontSize = 11.sp,
                )
            }
            if (v.bestMoveSan != v.moveSan && v.bestMoveSan.isNotEmpty()) {
                Text(
                    if (v.classification == "best") "Also strong: ${v.bestMoveSan}" else "Better: ${v.bestMoveSan}",
                    color = ChessCoachTheme.text.copy(alpha = 0.85f), fontSize = 13.sp,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            if (v.comment.isNotEmpty()) {
                Text(v.comment, color = ChessCoachTheme.mutedText, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
            }
        }
    }
}

@Composable
private fun MistakesList(mistakes: List<MoveReview>, viewModel: SavedGameReviewViewModel) {
    ThemedGlassCard(cornerRadius = 12, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
        Column(Modifier.padding(12.dp)) {
            Text("Mistakes", color = ChessCoachTheme.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            mistakes.forEachIndexed { index, m ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.gotoMistake(index) }
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "${m.moveNumber}${if (m.color == "white") "." else "..."} ${m.moveSan}",
                        color = ChessCoachTheme.text, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        m.classification.replaceFirstChar { it.uppercase() },
                        color = classificationColor(m.classification), fontSize = 12.sp,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("-${fmtPct(m.winSwing)}%", color = ChessCoachTheme.mutedText, fontSize = 12.sp)
                }
            }
        }
    }
}

private fun fmtPct(x: Double): String = if (x == x.toLong().toDouble()) x.toLong().toString() else "%.1f".format(x)
