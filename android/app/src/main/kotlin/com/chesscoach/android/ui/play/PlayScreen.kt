package com.chesscoach.android.ui.play

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.GameStatus
import com.chesscoach.core.chess.PieceType

@Composable
fun PlayScreen(viewModel: PlayViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var showSetup by remember { mutableStateOf(true) }

    Scaffold(topBar = { TopAppBar(title = { Text("Play") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            if (!state.engineAvailable) {
                Text(
                    "Stockfish engine binary not bundled in this build -- Play mode needs it " +
                        "to move for the opponent and grade your moves. See android/README.md.",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }

            ChessBoardView(
                board = state.board,
                whiteAtBottom = state.playerColor == Color.WHITE,
                selectedSquare = state.selected,
                legalTargets = state.legalTargets,
                lastMove = state.lastMove,
                onSquareClick = viewModel::onSquareTap,
            )

            Row(
                Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(onClick = viewModel::requestHint, enabled = state.isPlayerTurn && state.engineAvailable) {
                    Text("Hint")
                }
                OutlinedButton(onClick = viewModel::retakeLastMove, enabled = state.moveSan.isNotEmpty()) {
                    Text("Take back")
                }
                OutlinedButton(onClick = { showSetup = true }) { Text("New game") }
            }

            if (state.isEngineThinking) {
                Row(Modifier.padding(top = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                    Text("Thinking...")
                }
            }

            state.hint?.let { hint ->
                Text(
                    "Hint: ${hint.bestSan}" + (hint.altSan?.let { " (or $it)" } ?: ""),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            state.lastGrade?.let { grade ->
                Text("Last move: ${grade.label}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 4.dp))
            }
            state.openingName?.let { name ->
                Text(name, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 4.dp))
            }

            StatusBanner(state.status, state.playerColor)

            Text(
                "Moves: " + state.moveSan.joinToString(" "),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }

    state.pendingPromotion?.let {
        PromotionDialog(onChoose = viewModel::choosePromotion, onDismiss = viewModel::cancelPromotion)
    }

    if (showSetup) {
        GameSetupDialog(
            onStart = { color, skill ->
                viewModel.newGame(color, skill)
                showSetup = false
            },
            onDismiss = { showSetup = false },
        )
    }
}

@Composable
private fun StatusBanner(status: GameStatus, playerColor: Color) {
    val text = when (status) {
        GameStatus.CHECKMATE -> "Checkmate"
        GameStatus.STALEMATE -> "Stalemate"
        GameStatus.CHECK -> "Check"
        GameStatus.NORMAL -> return
    }
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun PromotionDialog(onChoose: (PieceType) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Promote to") },
        text = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT).forEach { type ->
                    TextButton(onClick = { onChoose(type) }) { Text(type.name.take(1)) }
                }
            }
        },
        confirmButton = {},
    )
}

@Composable
private fun GameSetupDialog(onStart: (Color, Int) -> Unit, onDismiss: () -> Unit) {
    var color by remember { mutableStateOf(Color.WHITE) }
    var skill by remember { mutableStateOf(10f) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New game") },
        text = {
            Column {
                Text("Play as")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(Color.WHITE, Color.BLACK).forEach { c ->
                        val selected = c == color
                        val label = (if (c == Color.WHITE) "White" else "Black") + if (selected) " *" else ""
                        OutlinedButton(onClick = { color = c }) { Text(label) }
                    }
                }
                Text("Opponent strength: ${skill.toInt()}/20", modifier = Modifier.padding(top = 16.dp))
                Slider(value = skill, onValueChange = { skill = it }, valueRange = 0f..20f, steps = 19)
            }
        },
        confirmButton = { Button(onClick = { onStart(color, skill.toInt()) }) { Text("Start") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
