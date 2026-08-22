package com.chesscoach.android.ui.openings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.board.ChessBoardView

@Composable
fun OpeningsScreen(viewModel: OpeningsViewModel) {
    val state by viewModel.state.collectAsState()

    Scaffold(topBar = { TopAppBar(title = { Text("Opening Trainer") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = state.query,
                onValueChange = viewModel::setQuery,
                label = { Text("Search (e.g. \"Sicilian\" or \"B20\")") },
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            )

            if (state.selected != null) {
                OpeningLinePlayer(state, viewModel)
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(state.lines) { line ->
                        ListItem(
                            headlineContent = { Text(line.name) },
                            supportingContent = { Text("${line.eco} - ${line.sanMoves.joinToString(" ")}", maxLines = 1) },
                            modifier = Modifier.clickable { viewModel.selectLine(line) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun OpeningLinePlayer(state: OpeningsUiState, viewModel: OpeningsViewModel) {
    val line = state.selected ?: return
    Column(Modifier.padding(16.dp)) {
        Text(line.name, style = MaterialTheme.typography.titleMedium)
        ChessBoardView(board = state.boards[state.plyIndex], modifier = Modifier.padding(top = 12.dp))
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = viewModel::stepBack, enabled = state.plyIndex > 0) { Text("< Prev") }
            OutlinedButton(onClick = viewModel::stepForward, enabled = state.plyIndex < state.boards.lastIndex) { Text("Next >") }
            OutlinedButton(onClick = viewModel::closeLine) { Text("Back to list") }
        }
        Text(
            line.sanMoves.joinToString(" "),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}
