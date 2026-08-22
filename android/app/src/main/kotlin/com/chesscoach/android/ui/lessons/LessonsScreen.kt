package com.chesscoach.android.ui.lessons

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.core.data.LessonCatalog

@Composable
fun LessonsScreen(onLessonClick: (String) -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text("Lessons") }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            LessonCatalog.stages.forEach { stage ->
                item {
                    Text(
                        stage.title,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    )
                }
                items(stage.lessons) { lesson ->
                    ListItem(
                        headlineContent = { Text(lesson.title) },
                        supportingContent = { Text(lesson.bodyText, maxLines = 2) },
                        modifier = Modifier.padding(horizontal = 8.dp).clickable { onLessonClick(lesson.id) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}
