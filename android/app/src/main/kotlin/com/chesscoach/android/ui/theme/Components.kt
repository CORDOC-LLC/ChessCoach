package com.chesscoach.android.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Themed screen shell: dark [ChessCoachTheme.bg] background, a big-title
 * header (matching iOS's large-title nav style rather than Material's
 * centered small `TopAppBar`), and an optional back button. Every ported
 * screen below `Play`/`Review`/etc. uses this instead of
 * `Scaffold`+`TopAppBar` so the whole app reads as one design system, not
 * Material chrome with a few themed cards dropped in.
 */
@Composable
fun ThemedScreen(
    title: String,
    onBack: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize().background(ChessCoachTheme.bg)) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onBack != null) {
                    Box(
                        modifier = Modifier
                            .size(34.dp)
                            .background(ChessCoachTheme.surface.copy(alpha = 0.8f), CircleShape)
                            .clickable(onClick = onBack),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = ChessCoachTheme.text.copy(alpha = 0.85f),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    Spacer(Modifier.padding(start = 8.dp))
                }
                Text(
                    title,
                    color = ChessCoachTheme.text,
                    fontFamily = ChessCoachTheme.displayFontFamily,
                    fontWeight = ChessCoachTheme.displayFontWeight,
                    fontSize = 28.sp,
                )
            }
            Column(
                modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                content = content,
            )
        }
    }
}

/** A themed list/content card -- `theme.cardBackgroundColor` fill,
 *  `theme.cardBorderColor` 1dp stroke, `Radius.card` (16dp) corners. Direct
 *  match for the repeated `.background(theme.cardBackgroundColor)
 *  .overlay(RoundedRectangle...stroke...).clipShape(...)` pattern used
 *  throughout the iOS source (`RootView.swift`'s `beginnersCard`/
 *  `weaknessReportCard`, etc). */
@Composable
fun ThemedCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(ChessCoachTheme.Radius.card.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .background(ChessCoachTheme.cardBackground, shape)
            .border(1.dp, ChessCoachTheme.cardBorder, shape)
            .padding(14.dp),
        content = content,
    )
}

@Composable
fun ThemedPrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .let { if (enabled) it.clickable(onClick = onClick) else it }
            .background(
                if (enabled) ChessCoachTheme.accent else ChessCoachTheme.accent.copy(alpha = 0.35f),
                RoundedCornerShape(ChessCoachTheme.Radius.pill.dp),
            )
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = ChessCoachTheme.onAccent, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun ThemedSecondaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(ChessCoachTheme.Radius.chip.dp)
    Box(
        modifier = modifier
            .let { if (enabled) it.clickable(onClick = onClick) else it }
            .border(1.dp, ChessCoachTheme.text.copy(alpha = if (enabled) 0.16f else 0.06f), shape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            color = if (enabled) ChessCoachTheme.text else ChessCoachTheme.faintText,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** A row inside a list-style screen -- title + subtitle, matching the
 *  iOS `gameRow`/puzzle-theme-row shape used across Puzzles/Lessons/Openings. */
@Composable
fun ThemedListRow(title: String, subtitle: String? = null, onClick: () -> Unit) {
    ThemedCard(onClick = onClick) {
        Text(title, color = ChessCoachTheme.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        if (subtitle != null) {
            Spacer(Modifier.padding(top = 2.dp))
            Text(subtitle, color = ChessCoachTheme.mutedText, fontSize = 13.sp)
        }
    }
}

val ListItemSpacing = Arrangement.spacedBy(10.dp)
