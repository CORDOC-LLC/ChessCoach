package com.chesscoach.android.ui.review

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.android.ui.theme.ThemedSecondaryButton

@Composable
fun ReviewScreen(viewModel: ReviewViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "Review", onBack = onBack) {
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
