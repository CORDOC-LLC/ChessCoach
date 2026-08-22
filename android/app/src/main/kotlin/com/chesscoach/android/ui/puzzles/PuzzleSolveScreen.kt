package com.chesscoach.android.ui.puzzles

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.core.chess.Color

@Composable
fun PuzzleSolveScreen(viewModel: PuzzleSolveViewModel) {
    val state by viewModel.state.collectAsState()

    Scaffold(topBar = { TopAppBar(title = { Text("${state.theme} - ${state.index + 1}/${state.puzzles.size}") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            if (state.isLoading) {
                Text("Loading...")
            } else if (state.currentPuzzle == null) {
                Text("No puzzles available for this theme.")
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
                    Text(it, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                }

                Row(
                    Modifier.fillMaxWidth().padding(top = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (state.feedback == PuzzleFeedback.INCORRECT) {
                        OutlinedButton(onClick = viewModel::retryPuzzle) { Text("Retry") }
                    }
                    Button(onClick = viewModel::nextPuzzle) { Text("Next puzzle") }
                }

                state.currentPuzzle?.let {
                    Text("Rating: ${it.rating}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp))
                }
            }
        }
    }
}
