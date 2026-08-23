package com.chesscoach.android.ui.openings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.chesscoach.android.ui.theme.ThemedListRow
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.android.ui.theme.ThemedSecondaryButton

@Composable
fun OpeningsScreen(viewModel: OpeningsViewModel) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "Openings") {
        OutlinedTextField(
            value = state.query,
            onValueChange = viewModel::setQuery,
            label = { Text("Search (e.g. \"Sicilian\" or \"B20\")") },
            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
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

        if (state.selected != null) {
            OpeningLinePlayer(state, viewModel)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.lines) { line ->
                    ThemedListRow(
                        title = line.name,
                        subtitle = "${line.eco} - ${line.sanMoves.joinToString(" ")}",
                        onClick = { viewModel.selectLine(line) },
                    )
                }
            }
        }
    }
}

@Composable
private fun OpeningLinePlayer(state: OpeningsUiState, viewModel: OpeningsViewModel) {
    val line = state.selected ?: return
    Column {
        Text(line.name, color = ChessCoachTheme.text, fontSize = 18.sp)
        ChessBoardView(board = state.boards[state.plyIndex], modifier = Modifier.padding(top = 12.dp))
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ThemedSecondaryButton("< Prev", enabled = state.plyIndex > 0, onClick = viewModel::stepBack)
            ThemedSecondaryButton("Next >", enabled = state.plyIndex < state.boards.lastIndex, onClick = viewModel::stepForward)
            ThemedSecondaryButton("Back to list", onClick = viewModel::closeLine)
        }
        Text(
            line.sanMoves.joinToString(" "),
            color = ChessCoachTheme.mutedText,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
    }
}
