package com.chesscoach.android.ui.play

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.android.ui.theme.ThemedSecondaryButton
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.GameStatus
import com.chesscoach.core.chess.PieceType

@Composable
fun PlayScreen(viewModel: PlayViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var showSetup by remember { mutableStateOf(true) }

    ThemedScreen(title = "Play", onBack = onBack) {
        if (!state.engineAvailable) {
            Text(
                "Stockfish engine binary not bundled in this build -- Play mode needs it " +
                    "to move for the opponent and grade your moves. See android/README.md.",
                color = ChessCoachTheme.mutedText,
                fontSize = 13.sp,
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
            ThemedSecondaryButton("Hint", enabled = state.isPlayerTurn && state.engineAvailable, onClick = viewModel::requestHint)
            ThemedSecondaryButton("Take back", enabled = state.moveSan.isNotEmpty(), onClick = viewModel::retakeLastMove)
            ThemedSecondaryButton("New game", onClick = { showSetup = true })
        }

        if (state.isEngineThinking) {
            Row(Modifier.padding(top = 12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                CircularProgressIndicator(color = ChessCoachTheme.accent, modifier = Modifier.padding(end = 8.dp))
                Text("Thinking...", color = ChessCoachTheme.mutedText, fontSize = 14.sp)
            }
        }

        state.hint?.let { hint ->
            Text(
                "Hint: ${hint.bestSan}" + (hint.altSan?.let { " (or $it)" } ?: ""),
                color = ChessCoachTheme.text,
                fontSize = 14.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        state.lastGrade?.let { grade ->
            Text("Last move: ${grade.label}", color = ChessCoachTheme.text, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp))
        }
        state.openingName?.let { name ->
            Text(name, color = ChessCoachTheme.accent2, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
        }

        StatusBanner(state.status)

        Text(
            "Moves: " + state.moveSan.joinToString(" "),
            color = ChessCoachTheme.mutedText,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
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
private fun StatusBanner(status: GameStatus) {
    val text = when (status) {
        GameStatus.CHECKMATE -> "Checkmate"
        GameStatus.STALEMATE -> "Stalemate"
        GameStatus.CHECK -> "Check"
        GameStatus.NORMAL -> return
    }
    Text(text, color = ChessCoachTheme.accent2, fontSize = 18.sp, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun PromotionDialog(onChoose: (PieceType) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChessCoachTheme.surface,
        titleContentColor = ChessCoachTheme.text,
        textContentColor = ChessCoachTheme.text,
        title = { Text("Promote to") },
        text = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT).forEach { type ->
                    ThemedSecondaryButton(type.name.take(1), onClick = { onChoose(type) })
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
        containerColor = ChessCoachTheme.surface,
        titleContentColor = ChessCoachTheme.text,
        textContentColor = ChessCoachTheme.text,
        title = { Text("New game") },
        text = {
            Column {
                Text("Play as", color = ChessCoachTheme.mutedText, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    listOf(Color.WHITE, Color.BLACK).forEach { c ->
                        val selected = c == color
                        val label = (if (c == Color.WHITE) "White" else "Black") + if (selected) " *" else ""
                        ThemedSecondaryButton(label, onClick = { color = c })
                    }
                }
                Text(
                    "Opponent strength: ${skill.toInt()}/20",
                    color = ChessCoachTheme.mutedText,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 16.dp),
                )
                Slider(
                    value = skill,
                    onValueChange = { skill = it },
                    valueRange = 0f..20f,
                    steps = 19,
                    colors = SliderDefaults.colors(
                        thumbColor = ChessCoachTheme.accent,
                        activeTrackColor = ChessCoachTheme.accent,
                        inactiveTrackColor = ChessCoachTheme.text.copy(alpha = 0.16f),
                    ),
                )
            }
        },
        confirmButton = { ThemedPrimaryButton("Start", modifier = Modifier.padding(bottom = 4.dp), onClick = { onStart(color, skill.toInt()) }) },
        dismissButton = { ThemedSecondaryButton("Cancel", onClick = onDismiss) },
    )
}
