package com.chesscoach.android.ui.lessons

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedListRow
import com.chesscoach.android.ui.theme.ThemedScreen
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
                    ThemedListRow(
                        title = lesson.title,
                        subtitle = lesson.bodyText,
                        onClick = { onLessonClick(lesson.id) },
                    )
                }
            }
        }
    }
}
