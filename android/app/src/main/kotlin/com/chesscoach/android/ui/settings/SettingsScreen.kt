package com.chesscoach.android.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.billing.ReviewEntitlementStore
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedListRow
import com.chesscoach.android.ui.theme.ThemedScreen

private data class LicenseFile(val label: String, val fileName: String)

private val LICENSE_FILES = listOf(
    LicenseFile("Notices (Stockfish, chesskit, Lichess data)", "NOTICE.md"),
    LicenseFile("chesskit (MIT)", "chesskit-mit.txt"),
    LicenseFile("GPLv3", "gplv3.txt"),
)

@Composable
fun SettingsScreen(
    assetRepository: AssetRepository,
    reviewEntitlementStore: ReviewEntitlementStore,
    onBack: () -> Unit,
    onUnlockReview: () -> Unit,
) {
    var selected by remember { mutableStateOf<LicenseFile?>(null) }
    var content by remember { mutableStateOf("") }
    val hasReviewAccess by reviewEntitlementStore.hasReviewAccess.collectAsState()

    LaunchedEffect(selected) {
        selected?.let { content = runCatching { assetRepository.licenseText(it.fileName) }.getOrDefault("Couldn't load ${it.fileName}.") }
    }

    ThemedScreen(
        title = selected?.label ?: "Settings",
        onBack = if (selected != null) { { selected = null } } else onBack,
    ) {
        if (selected == null) {
            Text(
                "ChessCoach for Android -- review tier. Stockfish plays and grades, " +
                    "fully on-device. No coach, no account. Purchases are handled by Google Play.",
                color = ChessCoachTheme.mutedText,
                fontSize = 14.sp,
                modifier = Modifier.padding(bottom = 16.dp),
            )
            if (hasReviewAccess) {
                ThemedListRow(
                    title = "Review Plan",
                    subtitle = "Unlocked -- full move analysis, forever",
                    icon = Icons.Filled.CheckCircle,
                    onClick = {},
                )
            } else {
                ThemedListRow(
                    title = "Unlock Full Review",
                    subtitle = "One-time purchase -- full move analysis beyond move 6",
                    icon = Icons.AutoMirrored.Filled.TrendingUp,
                    onClick = onUnlockReview,
                )
            }
            androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 10.dp))
            LazyColumn(modifier = Modifier.fillMaxSize().padding(bottom = 16.dp)) {
                items(LICENSE_FILES) { file ->
                    ThemedListRow(title = file.label, onClick = { selected = file })
                    androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 10.dp))
                }
            }
        } else {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                Text(content, color = ChessCoachTheme.mutedText, fontSize = 12.sp, modifier = Modifier.padding(bottom = 16.dp))
            }
        }
    }
}
