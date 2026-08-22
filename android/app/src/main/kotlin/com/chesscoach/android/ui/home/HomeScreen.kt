package com.chesscoach.android.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class HomeDestination(val title: String, val subtitle: String, val onClick: () -> Unit)

@Composable
fun HomeScreen(
    onPlay: () -> Unit,
    onReview: () -> Unit,
    onPuzzles: () -> Unit,
    onLessons: () -> Unit,
    onOpenings: () -> Unit,
    onSettings: () -> Unit,
) {
    val destinations = listOf(
        HomeDestination("Play", "Play against Stockfish with live move grading", onPlay),
        HomeDestination("Review", "Import a PGN and step through an engine-graded review", onReview),
        HomeDestination("Puzzles", "Thousands of tactics puzzles by theme, no daily limit", onPuzzles),
        HomeDestination("Lessons", "Start from zero, one concept at a time", onLessons),
        HomeDestination("Opening Trainer", "Drill the openings you actually play", onOpenings),
        HomeDestination("Settings", "Open source licenses and app info", onSettings),
    )

    Scaffold(topBar = { TopAppBar(title = { Text("ChessCoach") }) }) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(destinations) { destination ->
                Card(modifier = Modifier.fillMaxWidth(), onClick = destination.onClick) {
                    Column(Modifier.padding(16.dp)) {
                        Text(destination.title, style = MaterialTheme.typography.titleMedium)
                        Text(destination.subtitle, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }
}
