package com.chesscoach.android.ui.lessons

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.core.data.Lesson

@Composable
fun LessonDetailScreen(lesson: Lesson, onPractice: () -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text(lesson.title) }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState())) {
            Text(lesson.bodyText, style = MaterialTheme.typography.bodyLarge)
            Button(onClick = onPractice, modifier = Modifier.padding(top = 24.dp)) {
                Text("Practice ${lesson.puzzleCount} puzzles")
            }
        }
    }
}
