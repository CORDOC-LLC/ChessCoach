package com.chesscoach.android.ui.puzzles

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.android.ui.theme.ThemedSecondaryButton
import com.chesscoach.core.chess.Color

@Composable
fun PuzzleSolveScreen(viewModel: PuzzleSolveViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "${state.theme} - ${state.index + 1}/${state.puzzles.size}", onBack = onBack) {
        if (state.isLoading) {
            Text("Loading...", color = ChessCoachTheme.mutedText, fontSize = 14.sp)
        } else if (state.currentPuzzle == null) {
            Text("No puzzles available for this theme.", color = ChessCoachTheme.mutedText, fontSize = 14.sp)
        } else {
            ChessBoardView(
                board = state.board,
                whiteAtBottom = state.playerColor == Color.WHITE,
                selectedSquare = state.selected,
                legalTargets = state.legalTargets,
                lastMove = state.lastMove,
                onSquareClick = viewModel::onSquareTap,
            )

            val feedbackText = when (state.feedback) {
                PuzzleFeedback.CORRECT -> "Correct! Keep going."
                PuzzleFeedback.INCORRECT -> "Not quite -- try again."
                PuzzleFeedback.SOLVED -> "Solved!"
                PuzzleFeedback.NONE -> null
            }
            feedbackText?.let {
                Text(it, color = ChessCoachTheme.accent2, fontSize = 17.sp, modifier = Modifier.padding(top = 12.dp))
            }

            Row(
                Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (state.feedback == PuzzleFeedback.INCORRECT) {
                    ThemedSecondaryButton("Retry", onClick = viewModel::retryPuzzle)
                }
                ThemedPrimaryButton("Next puzzle", onClick = viewModel::nextPuzzle)
            }

            state.currentPuzzle?.let {
                Text("Rating: ${it.rating}", color = ChessCoachTheme.mutedText, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}
