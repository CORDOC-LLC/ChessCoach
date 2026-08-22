package com.chesscoach.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val GambitGreen = Color(0xFF3A6B4C)
val GambitGold = Color(0xFFC9A24B)
val BoardLight = Color(0xFFEDE6D6)
val BoardDark = Color(0xFF7D9473)
val BoardHighlight = Color(0x8AC9A24B)

private val LightColors = lightColorScheme(
    primary = GambitGreen,
    secondary = GambitGold,
)
private val DarkColors = darkColorScheme(
    primary = GambitGold,
    secondary = GambitGreen,
)

@Composable
fun ChessCoachTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) DarkColors else LightColors
    MaterialTheme(colorScheme = colors, content = content)
}
