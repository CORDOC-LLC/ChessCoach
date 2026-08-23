package com.chesscoach.android.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.theme.ChessCoachTheme

/** Mirrors iOS `HomeTab` (`RootView.swift`) -- same 4 tabs, same order, same
 *  icon mapping (`house.fill`/`book.fill`/`book.closed.fill`/`puzzlepiece.fill`
 *  -> the nearest Material equivalents, since there's no SF Symbols
 *  equivalent on Android and `material-icons-extended` is already a
 *  dependency here, so this doesn't add a new one for a handful of glyphs). */
enum class HomeTab(val title: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Lessons("Lessons", Icons.Filled.MenuBook),
    Openings("Openings", Icons.Filled.Book),
    Puzzles("Puzzles", Icons.Filled.Extension),
}

/** Direct port of iOS `GlobalTabBar` -- present on Home/Lessons/Openings/
 *  Puzzles' list screens, hidden while a chessboard is actually on screen
 *  (Play, a puzzle/lesson solve session, Review's analysis view), matching
 *  the iOS comment's exact reasoning: give that space back to the move
 *  list/board instead of wasting it on a nav bar mid-game. */
@Composable
fun GlobalTabBar(activeTab: HomeTab, onSelect: (HomeTab) -> Unit) {
    Column(modifier = Modifier.fillMaxWidth().background(ChessCoachTheme.cardBackground)) {
        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(ChessCoachTheme.cardBorder))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(PaddingValues(top = 10.dp, bottom = 8.dp)),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            HomeTab.entries.forEach { tab ->
                TabBarItem(tab = tab, selected = tab == activeTab, onClick = { onSelect(tab) })
            }
        }
    }
}

@Composable
private fun TabBarItem(tab: HomeTab, selected: Boolean, onClick: () -> Unit) {
    val tint = if (selected) ChessCoachTheme.accent else ChessCoachTheme.text.copy(alpha = 0.6f)
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .width(72.dp)
            .clickable(interactionSource = interactionSource, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(tab.icon, contentDescription = null, tint = tint, modifier = Modifier.height(20.dp))
            Spacer(Modifier.height(4.dp))
            Text(tab.title, color = tint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}
