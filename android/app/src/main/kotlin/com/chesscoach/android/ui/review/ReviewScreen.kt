package com.chesscoach.android.ui.review

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedCard
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.android.ui.theme.ThemedSecondaryButton

@Composable
fun ReviewScreen(viewModel: ReviewViewModel, onBack: () -> Unit, onOpenSavedGame: (String) -> Unit = {}) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "Review", onBack = onBack) {
        MyGamesSection(state.savedGames, onOpenSavedGame)

        Text(
            "Or paste a game (PGN)",
            color = ChessCoachTheme.mutedText,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 16.dp, bottom = 6.dp),
        )
        OutlinedTextField(
            value = state.pgnInput,
            onValueChange = viewModel::setPgnInput,
            label = { Text("Paste PGN") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            shape = RoundedCornerShape(ChessCoachTheme.Radius.chip.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = ChessCoachTheme.text,
                unfocusedTextColor = ChessCoachTheme.text,
                focusedBorderColor = ChessCoachTheme.accent,
                unfocusedBorderColor = ChessCoachTheme.text.copy(alpha = 0.2f),
                focusedLabelColor = ChessCoachTheme.accent2,
                unfocusedLabelColor = ChessCoachTheme.mutedText,
                cursorColor = ChessCoachTheme.accent,
            ),
        )
        ThemedPrimaryButton("Import", modifier = Modifier.padding(top = 10.dp), onClick = viewModel::importPgn)
        state.error?.let {
            Text(it, color = ChessCoachTheme.accent2, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
        }

        if (!state.engineAvailable) {
            Text(
                "Stockfish engine binary not bundled in this build -- board replay works, " +
                    "but per-position evaluation needs it. See android/README.md.",
                color = ChessCoachTheme.mutedText,
                fontSize = 13.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }

        ChessBoardView(board = state.board, modifier = Modifier.padding(top = 16.dp))

        Row(
            Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            ThemedSecondaryButton("< Prev", enabled = state.canStepBack, onClick = viewModel::stepBack)
            ThemedSecondaryButton("Next >", enabled = state.canStepForward, onClick = viewModel::stepForward)
        }

        Text(
            "Position ${state.index} / ${state.boards.lastIndex}",
            color = ChessCoachTheme.mutedText,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp),
        )
        state.evalCp?.let { cp ->
            Text("Eval: ${"%.1f".format(cp / 100.0)}", color = ChessCoachTheme.text, fontSize = 14.sp)
        }
        if (state.isAnalyzing) Text("Analyzing...", color = ChessCoachTheme.mutedText, fontSize = 13.sp)
        state.openingName?.let { Text(it, color = ChessCoachTheme.accent2, fontSize = 13.sp) }

        Text(
            "Moves: " + state.moveSan.joinToString(" "),
            color = ChessCoachTheme.mutedText,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
    }
}

/** "My games" -- every Play-mode game saved on this device, most recent
 *  first. A finished game with complete data opens the full win-graph/
 *  mistakes review; an in-progress or too-old-to-rebuild game just shows a
 *  status label instead of a tap target. Port of iOS `SavedGamesView`. */
@Composable
private fun MyGamesSection(games: List<com.chesscoach.core.chess.SavedGame>, onOpenSavedGame: (String) -> Unit) {
    Text(
        "My games",
        color = ChessCoachTheme.text,
        fontSize = 16.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(bottom = 6.dp),
    )
    Text(
        "Saved on this device only -- never uploaded anywhere.",
        color = ChessCoachTheme.faintText,
        fontSize = 11.sp,
        modifier = Modifier.padding(bottom = 8.dp),
    )
    if (games.isEmpty()) {
        Text(
            "No games saved yet. Play a game and it'll show up here.",
            color = ChessCoachTheme.mutedText,
            fontSize = 13.sp,
        )
        return
    }
    games.forEach { game ->
        val reviewable = SavedGameRowFormatter.isReviewable(game)
        ThemedCard(
            modifier = Modifier.padding(bottom = 8.dp),
            onClick = if (reviewable) ({ onOpenSavedGame(game.id) }) else null,
        ) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(SavedGameRowFormatter.title(game), color = ChessCoachTheme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.padding(top = 2.dp))
                    Text(SavedGameRowFormatter.subtitle(game), color = ChessCoachTheme.mutedText, fontSize = 12.sp)
                }
                if (!reviewable) {
                    Text(
                        if (game.isGameOver) "Not reviewable" else "In progress",
                        color = ChessCoachTheme.faintText, fontSize = 11.sp,
                    )
                }
            }
        }
    }
}
