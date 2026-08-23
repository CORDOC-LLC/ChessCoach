package com.chesscoach.core.chess

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

/** One graded ply the user played -- port of iOS `CoachPromptBuilder.PlayMoveRecord`. */
data class PlayMoveRecord(
    val moveNumber: Int,
    val san: String,
    val classification: String,
    val winBefore: Double,
    val winAfter: Double,
    val betterSan: String?,
    val bestUci: String?,
    val fen: String?,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("moveNumber", moveNumber)
        put("san", san)
        put("classification", classification)
        put("winBefore", winBefore)
        put("winAfter", winAfter)
        betterSan?.let { put("betterSan", it) }
        bestUci?.let { put("bestUci", it) }
        fen?.let { put("fen", it) }
    }

    companion object {
        fun fromJson(obj: JsonObject) = PlayMoveRecord(
            moveNumber = obj["moveNumber"]!!.jsonPrimitive.int,
            san = obj["san"]!!.jsonPrimitive.content,
            classification = obj["classification"]!!.jsonPrimitive.content,
            winBefore = obj["winBefore"]!!.jsonPrimitive.double,
            winAfter = obj["winAfter"]!!.jsonPrimitive.double,
            betterSan = obj["betterSan"]?.jsonPrimitive?.contentOrNull,
            bestUci = obj["bestUci"]?.jsonPrimitive?.contentOrNull,
            fen = obj["fen"]?.jsonPrimitive?.contentOrNull,
        )
    }
}

/**
 * One Play-mode game, at whatever point it was last checkpointed -- port of
 * iOS `SavedGame.swift`. Stored on-device only, one JSON file per game (see
 * the app module's `SavedGameStore` for file I/O); everything here is the
 * pure data shape + manual JSON (de)serialization using kotlinx.serialization's
 * JsonObject builder API (no `@Serializable`/compiler-plugin dependency needed).
 */
data class SavedGame(
    val id: String,
    val startedAt: Long,
    val updatedAt: Long,
    val playerIsWhite: Boolean,
    val startFen: String,
    val moves: List<String>,
    val sanMoves: List<String>,
    val fenHistory: List<String>,
    val skill: Int,
    val isGameOver: Boolean,
    val resultText: String?,
    val openingName: String?,
    val openingEco: String?,
    val moveRecords: List<PlayMoveRecord>,
    val winAfterMover: List<Double>?,
) {
    val sideLabel: String get() = if (playerIsWhite) "White" else "Black"

    fun toJson(): JsonObject = buildJsonObject {
        put("id", id)
        put("startedAt", startedAt)
        put("updatedAt", updatedAt)
        put("playerIsWhite", playerIsWhite)
        put("startFen", startFen)
        put("moves", buildJsonArray { moves.forEach { add(JsonPrimitive(it)) } })
        put("sanMoves", buildJsonArray { sanMoves.forEach { add(JsonPrimitive(it)) } })
        put("fenHistory", buildJsonArray { fenHistory.forEach { add(JsonPrimitive(it)) } })
        put("skill", skill)
        put("isGameOver", isGameOver)
        resultText?.let { put("resultText", it) }
        openingName?.let { put("openingName", it) }
        openingEco?.let { put("openingEco", it) }
        put("moveRecords", buildJsonArray { moveRecords.forEach { add(it.toJson()) } })
        winAfterMover?.let { list -> put("winAfterMover", buildJsonArray { list.forEach { add(JsonPrimitive(it)) } }) }
    }

    companion object {
        fun fromJson(obj: JsonObject): SavedGame = SavedGame(
            id = obj["id"]!!.jsonPrimitive.content,
            startedAt = obj["startedAt"]!!.jsonPrimitive.long,
            updatedAt = obj["updatedAt"]!!.jsonPrimitive.long,
            playerIsWhite = obj["playerIsWhite"]!!.jsonPrimitive.boolean,
            startFen = obj["startFen"]!!.jsonPrimitive.content,
            moves = obj["moves"]!!.jsonArray.map { it.jsonPrimitive.content },
            sanMoves = obj["sanMoves"]!!.jsonArray.map { it.jsonPrimitive.content },
            fenHistory = obj["fenHistory"]!!.jsonArray.map { it.jsonPrimitive.content },
            skill = obj["skill"]!!.jsonPrimitive.int,
            isGameOver = obj["isGameOver"]!!.jsonPrimitive.boolean,
            resultText = obj["resultText"]?.jsonPrimitive?.contentOrNull,
            openingName = obj["openingName"]?.jsonPrimitive?.contentOrNull,
            openingEco = obj["openingEco"]?.jsonPrimitive?.contentOrNull,
            moveRecords = (obj["moveRecords"] as? JsonArray)?.map { PlayMoveRecord.fromJson(it.jsonObject) } ?: emptyList(),
            winAfterMover = (obj["winAfterMover"] as? JsonArray)?.map { it.jsonPrimitive.double },
        )
    }
}
