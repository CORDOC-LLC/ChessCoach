package com.chesscoach.android.ui.lessons

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedCard
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.core.data.Lesson
import com.chesscoach.core.data.LessonCatalog

@Composable
fun LessonsScreen(onLessonClick: (String) -> Unit) {
    ThemedScreen(title = "Lessons") {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            LessonCatalog.stages.forEach { stage ->
                item {
                    Text(
                        stage.title,
                        color = ChessCoachTheme.accent2,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp,
                        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
                    )
                }
                items(stage.lessons) { lesson ->
                    LessonRow(lesson = lesson, onClick = { onLessonClick(lesson.id) })
                }
            }
        }
    }
}

@Composable
private fun LessonRow(lesson: Lesson, onClick: () -> Unit) {
    ThemedCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.AutoMirrored.Filled.MenuBook,
                contentDescription = null,
                tint = ChessCoachTheme.accent2,
                modifier = Modifier.size(22.dp).width(26.dp),
            )
            Spacer(Modifier.width(12.dp))
            Text(
                lesson.title,
                color = ChessCoachTheme.text,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                "${lesson.puzzleCount} puzzles",
                color = ChessCoachTheme.mutedText,
                fontSize = 13.sp,
            )
        }
    }
}
