package com.chesscoach.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.graphics.toArgb
import androidx.core.view.WindowCompat
import com.chesscoach.android.ui.navigation.ChessCoachNavHost
import com.chesscoach.android.ui.theme.ChessCoachAppTheme
import com.chesscoach.android.ui.theme.ChessCoachTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The Gambit preset is always dark, regardless of the system's own
        // light/dark setting -- force light (i.e. white/pale) system bar
        // icons rather than letting enableEdgeToEdge() infer from the
        // system, which would render dark status/nav bar icons invisible
        // against this always-dark background.
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        window.statusBarColor = ChessCoachTheme.bg.toArgb()
        window.navigationBarColor = ChessCoachTheme.bg.toArgb()
        val app = application as ChessCoachApp
        setContent {
            ChessCoachAppTheme {
                ChessCoachNavHost(
                    assetRepository = app.assetRepository,
                    engineProvider = app.engineProvider,
                    savedGameStore = app.savedGameStore,
                )
            }
        }
    }
}
