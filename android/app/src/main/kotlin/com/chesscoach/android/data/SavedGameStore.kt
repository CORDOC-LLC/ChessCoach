package com.chesscoach.android.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.chesscoach.core.chess.SavedGame
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

private val Context.chessCoachPrefs by preferencesDataStore(name = "chesscoach_prefs")
private val IN_PROGRESS_GAME_ID = stringPreferencesKey("savedGames.inProgressGameId")

/**
 * On-device store for [SavedGame]s -- one JSON file per game under this app's
 * private files dir, so a mid-game checkpoint only rewrites that game's small
 * file. Port of iOS `SavedGameStore`. Everything stays on-device: no saved
 * game is ever sent anywhere.
 */
class SavedGameStore(private val context: Context) {

    private val dir: File get() = File(context.filesDir, "savedGames").apply { mkdirs() }

    private fun path(id: String) = File(dir, "$id.json")

    suspend fun save(game: SavedGame) = withContext(Dispatchers.IO) {
        val tmp = File(dir, "${game.id}.json.tmp")
        tmp.writeText(Json.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), game.toJson()))
        tmp.renameTo(path(game.id))
    }

    suspend fun load(id: String): SavedGame? = withContext(Dispatchers.IO) {
        runCatching {
            val text = path(id).readText()
            SavedGame.fromJson(Json.parseToJsonElement(text).let { it as kotlinx.serialization.json.JsonObject })
        }.getOrNull()
    }

    /** Every saved game, most-recently-updated first. Corrupt/unreadable files
     *  are skipped rather than failing the whole list. */
    suspend fun loadAll(): List<SavedGame> = withContext(Dispatchers.IO) {
        val files = dir.listFiles { f -> f.extension == "json" } ?: emptyArray()
        files.mapNotNull { f ->
            runCatching {
                SavedGame.fromJson(Json.parseToJsonElement(f.readText()).let { it as kotlinx.serialization.json.JsonObject })
            }.getOrNull()
        }.sortedByDescending { it.updatedAt }
    }

    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        path(id).delete()
        Unit
    }

    suspend fun inProgressGameId(): String? =
        context.chessCoachPrefs.data.first()[IN_PROGRESS_GAME_ID]

    suspend fun setInProgressGameId(id: String?) {
        context.chessCoachPrefs.edit { prefs ->
            if (id != null) prefs[IN_PROGRESS_GAME_ID] = id else prefs.remove(IN_PROGRESS_GAME_ID)
        }
    }

    companion object {
        fun newId(): String = UUID.randomUUID().toString()
    }
}
