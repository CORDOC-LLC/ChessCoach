package com.chesscoach.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.chesscoach.android.ui.navigation.ChessCoachNavHost
import com.chesscoach.android.ui.theme.ChessCoachTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as ChessCoachApp
        setContent {
            ChessCoachTheme {
                ChessCoachNavHost(
                    assetRepository = app.assetRepository,
                    engineProvider = app.engineProvider,
                )
            }
        }
    }
}
