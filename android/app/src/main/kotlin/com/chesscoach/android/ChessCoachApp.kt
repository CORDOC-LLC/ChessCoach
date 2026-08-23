package com.chesscoach.android

import android.app.Application
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.data.SavedGameStore
import com.chesscoach.android.engine.EngineProvider

/** Minimal manual DI container -- no Hilt/Dagger, so there's nothing here that
 *  needs the Google Maven repo (unreachable from this build environment) beyond
 *  the Android Gradle Plugin itself. */
class ChessCoachApp : Application() {
    lateinit var assetRepository: AssetRepository
        private set
    lateinit var engineProvider: EngineProvider
        private set
    lateinit var savedGameStore: SavedGameStore
        private set

    override fun onCreate() {
        super.onCreate()
        assetRepository = AssetRepository(this)
        engineProvider = EngineProvider(this)
        savedGameStore = SavedGameStore(this)
    }
}
