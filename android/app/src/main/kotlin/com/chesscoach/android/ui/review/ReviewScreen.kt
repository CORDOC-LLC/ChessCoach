package com.chesscoach.android.ui.review

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.board.ChessBoardView

@Composable
fun ReviewScreen(viewModel: ReviewViewModel) {
    val state by viewModel.state.collectAsState()

    Scaffold(topBar = { TopAppBar(title = { Text("Review") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            OutlinedTextField(
                value = state.pgnInput,
                onValueChange = viewModel::setPgnInput,
                label = { Text("Paste PGN") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            Button(onClick = viewModel::importPgn, modifier = Modifier.padding(top = 8.dp)) {
                Text("Import")
            }
            state.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            }

            if (!state.engineAvailable) {
                Text(
                    "Stockfish engine binary not bundled in this build -- board replay works, " +
                        "but per-position evaluation needs it. See android/README.md.",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }

            ChessBoardView(board = state.board, modifier = Modifier.padding(top = 16.dp))

            Row(
                Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(onClick = viewModel::stepBack, enabled = state.canStepBack) { Text("< Prev") }
                OutlinedButton(onClick = viewModel::stepForward, enabled = state.canStepForward) { Text("Next >") }
            }

            Text(
                "Position ${state.index} / ${state.boards.lastIndex}",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )
            state.evalCp?.let { cp ->
                Text("Eval: ${"%.1f".format(cp / 100.0)}", style = MaterialTheme.typography.bodyMedium)
            }
            if (state.isAnalyzing) Text("Analyzing...", style = MaterialTheme.typography.bodySmall)
            state.openingName?.let { Text(it, style = MaterialTheme.typography.labelMedium) }

            Text(
                "Moves: " + state.moveSan.joinToString(" "),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}
