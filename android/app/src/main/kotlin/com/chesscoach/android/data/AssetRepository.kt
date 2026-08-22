package com.chesscoach.android.data

import android.content.Context
import com.chesscoach.core.data.Openings
import com.chesscoach.core.data.Puzzle
import com.chesscoach.core.data.PuzzleCatalog
import com.chesscoach.core.data.PuzzleThemeInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Loads the bundled puzzle/ECO/license data out of `assets/` and hands back
 *  parsed [com.chesscoach.core] models. Everything here is a plain asset read --
 *  no network, matching the review-only build's offline-first contract. */
class AssetRepository(private val context: Context) {

    private var cachedCatalog: List<PuzzleThemeInfo>? = null
    private var cachedOpenings: Openings? = null
    private val puzzleCache = mutableMapOf<String, List<Puzzle>>()

    private fun readAsset(path: String): String =
        context.assets.open(path).bufferedReader().use { it.readText() }

    suspend fun puzzleThemes(): List<PuzzleThemeInfo> = withContext(Dispatchers.IO) {
        cachedCatalog ?: PuzzleCatalog.parseCatalog(readAsset("puzzles/catalog.json")).also { cachedCatalog = it }
    }

    suspend fun puzzles(theme: PuzzleThemeInfo): List<Puzzle> = withContext(Dispatchers.IO) {
        puzzleCache.getOrPut(theme.theme) {
            PuzzleCatalog.parsePuzzles(readAsset("puzzles/${theme.file}"))
        }
    }

    suspend fun openings(): Openings = withContext(Dispatchers.IO) {
        cachedOpenings ?: Openings.load(
            listOf("a", "b", "c", "d", "e").map { readAsset("eco/$it.tsv") }
        ).also { cachedOpenings = it }
    }

    suspend fun licenseText(fileName: String): String = withContext(Dispatchers.IO) {
        readAsset("licenses/$fileName")
    }
}
