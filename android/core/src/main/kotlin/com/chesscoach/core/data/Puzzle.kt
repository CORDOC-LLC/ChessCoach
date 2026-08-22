package com.chesscoach.core.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One Lichess puzzle: a starting FEN and a UCI move sequence (opponent move,
 *  then the solution move(s)), vendored under `PuzzleData/` (CC0). */
data class Puzzle(
    val id: String,
    val fen: String,
    val moves: List<String>,
    val rating: Int,
    val themes: List<String>,
)

/** One entry from `puzzles/catalog.json` -- describes a bundled theme pack without
 *  loading its (much larger) puzzle file. */
data class PuzzleThemeInfo(
    val theme: String,
    val count: Int,
    val minRating: Int,
    val maxRating: Int,
    val file: String,
)

object PuzzleCatalog {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseCatalog(catalogJson: String): List<PuzzleThemeInfo> {
        val root = json.parseToJsonElement(catalogJson).jsonObject
        val themes = root["themes"]?.jsonArray ?: JsonArray(emptyList())
        return themes.map { element ->
            val obj = element.jsonObject
            PuzzleThemeInfo(
                theme = obj.getValue("theme").jsonPrimitive.content,
                count = obj.getValue("count").jsonPrimitive.content.toInt(),
                minRating = obj.getValue("minRating").jsonPrimitive.content.toInt(),
                maxRating = obj.getValue("maxRating").jsonPrimitive.content.toInt(),
                file = obj.getValue("file").jsonPrimitive.content,
            )
        }
    }

    /** Parses one theme's puzzle file, e.g. the contents of `fork.json`. */
    fun parsePuzzles(themeJson: String): List<Puzzle> {
        val root = json.parseToJsonElement(themeJson).jsonObject
        val puzzles = root["puzzles"]?.jsonArray ?: JsonArray(emptyList())
        return puzzles.map { element ->
            val obj = element.jsonObject
            Puzzle(
                id = obj.getValue("id").jsonPrimitive.content,
                fen = obj.getValue("fen").jsonPrimitive.content,
                moves = obj.getValue("moves").jsonArray.map { it.jsonPrimitive.content },
                rating = obj.getValue("rating").jsonPrimitive.content.toInt(),
                themes = obj.getValue("themes").jsonArray.map { it.jsonPrimitive.content },
            )
        }
    }
}
