package com.chesscoach.android.ui.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.R
import com.chesscoach.android.ui.theme.ChessCoachTheme

/**
 * Direct port of iOS `HomeView` (`RootView.swift`): decorative rule, crown
 * emblem, wordmark + theme-name label + subtitle, one primary pill CTA, one
 * secondary action card, a settings button in the top-right corner.
 *
 * Narrower than iOS's own Home: no Scan (no coach/vision on Android) and no
 * separate Import card (Android's Review screen absorbs PGN import inline,
 * matching this build's actual feature set rather than iOS's superset).
 */
@Composable
fun HomeScreen(
    onPlay: () -> Unit,
    onReview: () -> Unit,
    onSettings: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize().background(ChessCoachTheme.bg)) {
        // Soft radial glow behind the whole screen -- same role as iOS's
        // `theme.backgroundGradient` (a RadialGradient keyed off accent2,
        // centered slightly above the top edge).
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(ChessCoachTheme.glow, Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset.Unspecified,
                        radius = 1400f,
                    )
                )
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ChessCoachTheme.Space.s32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(40.dp))
            DecoRule()
            Spacer(Modifier.height(ChessCoachTheme.Space.s12.dp))
            Emblem()
            Spacer(Modifier.height(ChessCoachTheme.Space.s12.dp))
            Text(
                "ChessCoach",
                color = ChessCoachTheme.text,
                fontFamily = ChessCoachTheme.displayFontFamily,
                fontWeight = ChessCoachTheme.displayFontWeight,
                fontSize = 44.sp,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "THE GAMBIT ROOM",
                color = ChessCoachTheme.accent2,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 3.sp,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "Play with real engine analysis, or revisit the games that got away.",
                color = ChessCoachTheme.mutedText,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
                lineHeight = 20.sp,
            )

            Spacer(Modifier.height(28.dp))

            PrimaryButton(text = "Play a game", icon = Icons.Filled.PlayArrow, onClick = onPlay)

            Spacer(Modifier.height(ChessCoachTheme.Space.s12.dp))

            SecondaryActionCard(icon = Icons.Filled.Search, title = "Review", onClick = onReview)

            Spacer(Modifier.height(24.dp))
        }

        SettingsButton(onClick = onSettings, modifier = Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(top = 12.dp, end = 16.dp))
    }
}

@Composable
private fun DecoRule() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        DecoLine()
        Box(
            modifier = Modifier
                .size(6.dp)
                .background(ChessCoachTheme.accent2.copy(alpha = 0.9f), RoundedCornerShape(1.dp))
        )
        DecoLine()
    }
}

@Composable
private fun DecoLine() {
    Box(
        modifier = Modifier
            .width(50.dp)
            .height(1.dp)
            .background(
                Brush.horizontalGradient(
                    listOf(ChessCoachTheme.accent2.copy(alpha = 0f), ChessCoachTheme.accent2.copy(alpha = 0.9f))
                )
            )
    )
}

@Composable
private fun Emblem() {
    Box(
        modifier = Modifier
            .size(90.dp)
            .background(ChessCoachTheme.surface.copy(alpha = 0.8f), RoundedCornerShape(ChessCoachTheme.Radius.emblem.dp))
            .border(1.dp, ChessCoachTheme.accent.copy(alpha = 0.45f), RoundedCornerShape(ChessCoachTheme.Radius.emblem.dp)),
        contentAlignment = Alignment.Center,
    ) {
        // The same crown asset extracted from the iOS app icon for the
        // adaptive-icon foreground layer -- exact same mark, tinted with
        // the accent color the way iOS tints `crown.fill`.
        Image(
            painter = painterResource(R.drawable.ic_launcher_monochrome),
            contentDescription = null,
            colorFilter = ColorFilter.tint(ChessCoachTheme.accent),
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(64.dp),
        )
    }
}

@Composable
private fun PrimaryButton(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(ChessCoachTheme.accent, RoundedCornerShape(ChessCoachTheme.Radius.pill.dp))
            .padding(vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = ChessCoachTheme.onAccent, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = ChessCoachTheme.onAccent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SecondaryActionCard(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .border(1.dp, ChessCoachTheme.text.copy(alpha = 0.16f), RoundedCornerShape(ChessCoachTheme.Radius.chip.dp))
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = null, tint = ChessCoachTheme.accent2, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(10.dp))
        Text(title, color = ChessCoachTheme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SettingsButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(34.dp)
            .background(ChessCoachTheme.surface.copy(alpha = 0.8f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Filled.Settings,
            contentDescription = "Settings",
            tint = ChessCoachTheme.text.copy(alpha = 0.8f),
            modifier = Modifier.size(18.dp),
        )
    }
}
