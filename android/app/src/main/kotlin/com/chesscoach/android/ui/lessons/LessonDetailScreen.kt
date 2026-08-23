package com.chesscoach.android.ui.lessons

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedScreen
import com.chesscoach.core.data.Lesson

@Composable
fun LessonDetailScreen(lesson: Lesson, onBack: () -> Unit, onPractice: () -> Unit) {
    ThemedScreen(title = lesson.title, onBack = onBack) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text(lesson.bodyText, color = ChessCoachTheme.text, fontSize = 16.sp, lineHeight = 22.sp)
            ThemedPrimaryButton(
                "Practice ${lesson.puzzleCount} puzzles",
                modifier = Modifier.padding(top = 24.dp, bottom = 16.dp),
                onClick = onPractice,
            )
        }
    }
}
