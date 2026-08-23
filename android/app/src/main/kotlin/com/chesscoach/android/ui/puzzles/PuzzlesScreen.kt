package com.chesscoach.android.ui.puzzles

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Extension
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.theme.ThemedListRow
import com.chesscoach.android.ui.theme.ThemedScreen

@Composable
fun PuzzlesScreen(viewModel: PuzzlesViewModel, onThemeClick: (String) -> Unit) {
    val state by viewModel.state.collectAsState()

    ThemedScreen(title = "Puzzles") {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(state.themes) { theme ->
                ThemedListRow(
                    title = theme.theme,
                    subtitle = "${theme.count} puzzles - rating ${theme.minRating}-${theme.maxRating}",
                    icon = Icons.Filled.Extension,
                    onClick = { onThemeClick(theme.theme) },
                )
            }
        }
    }
}
