package com.chesscoach.android.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.chesscoach.android.data.AssetRepository

private data class LicenseFile(val label: String, val fileName: String)

private val LICENSE_FILES = listOf(
    LicenseFile("Notices (Stockfish, chesskit, Lichess data)", "NOTICE.md"),
    LicenseFile("chesskit (MIT)", "chesskit-mit.txt"),
    LicenseFile("GPLv3", "gplv3.txt"),
)

@Composable
fun SettingsScreen(assetRepository: AssetRepository) {
    var selected by remember { mutableStateOf<LicenseFile?>(null) }
    var content by remember { mutableStateOf("") }

    LaunchedEffect(selected) {
        selected?.let { content = runCatching { assetRepository.licenseText(it.fileName) }.getOrDefault("Couldn't load ${it.fileName}.") }
    }

    Scaffold(topBar = { TopAppBar(title = { Text(selected?.label ?: "Settings") }) }) { padding ->
        if (selected == null) {
            Column(Modifier.fillMaxSize().padding(padding)) {
                Text(
                    "ChessCoach for Android -- review tier. Stockfish plays and grades, " +
                        "fully on-device. No coach, no account, no network.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(16.dp),
                )
                LazyColumn {
                    items(LICENSE_FILES) { file ->
                        ListItem(
                            headlineContent = { Text(file.label) },
                            modifier = Modifier.clickable { selected = file },
                        )
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState())) {
                Text(content, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
