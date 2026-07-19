//  SavedGameToGameRecordTests.swift
//  U1 -- `HistoryStore.buildGameRecord(from: SavedGame, identity:)`, the bridge that
//  lets Play mode's own games enter the same `GameRecord` pipeline Review mode's
//  imported games already populate (KTD-1/KTD-2/KTD-5).

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("SavedGame -> GameRecord bridge")
struct SavedGameToGameRecordTests {

    private let standardStartFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// A `SavedGame` fixture with `plyCount` plies, all placeholder positions (the
    /// standard start FEN repeated), and whatever `moveRecords` the caller supplies
    /// for the USER's plies (in play order). Good enough for tests that don't care
    /// about real chess legality (counts/exclusion/nil-bestUCI/side), which don't
    /// need `Motifs.tagMotifs` to fire.
    private func savedGame(
        playerIsWhite: Bool = true,
        plyCount: Int,
        resultText: String? = "Checkmate — you win! 🎉",
        moveRecords: [CoachPromptBuilder.PlayMoveRecord],
        fenOverrides: [Int: String] = [:]
    ) -> SavedGame {
        let moves = (0..<plyCount).map { _ in "a2a3" }
        let sanMoves = (0..<plyCount).map { _ in "a3" }
        var fenHistory = (0...plyCount).map { _ in standardStartFEN }
        for (idx, fen) in fenOverrides { fenHistory[idx] = fen }
        return SavedGame(
            id: UUID(), startedAt: Date(), updatedAt: Date(), playerIsWhite: playerIsWhite,
            startFEN: standardStartFEN, moves: moves, sanMoves: sanMoves, fenHistory: fenHistory,
            skill: 6, isGameOver: true, resultText: resultText, openingName: nil, openingECO: nil,
            moveNotes: [:], gameSummary: nil, moveRecords: moveRecords)
    }

    @Test("counts.mistake/counts.blunder match one-each normal/mistake/blunder records")
    func countsMatchClassifications() throws {
        let records = [
            CoachPromptBuilder.PlayMoveRecord(
                moveNumber: 1, san: "a3", classification: "best",
                winBefore: 50, winAfter: 50, betterSan: nil, bestUCI: nil),
            CoachPromptBuilder.PlayMoveRecord(
                moveNumber: 2, san: "a3", classification: "mistake",
                winBefore: 60, winAfter: 45, betterSan: "Nf3", bestUCI: nil),
            CoachPromptBuilder.PlayMoveRecord(
                moveNumber: 3, san: "a3", classification: "blunder",
                winBefore: 55, winAfter: 20, betterSan: "Qd2", bestUCI: nil),
        ]
        let game = savedGame(plyCount: 10, moveRecords: records)

        let record = try #require(HistoryStore().buildGameRecord(from: game, identity: PlayerIdentity()))
        #expect(record.counts.mistake == 1)
        #expect(record.counts.blunder == 1)
        #expect(record.counts.inaccuracy == 0)
    }

    @Test("a game under the 10-ply floor is excluded entirely")
    func underFloorExcluded() {
        let game = savedGame(plyCount: 8, moveRecords: [])
        let record = HistoryStore().buildGameRecord(from: game, identity: PlayerIdentity())
        #expect(record == nil)
    }

    @Test("a PlayMoveRecord with bestUCI == nil still bridges, without a crash or motif tag")
    func nilBestUCIDegradesGracefully() throws {
        let records = [
            CoachPromptBuilder.PlayMoveRecord(
                moveNumber: 1, san: "a3", classification: "blunder",
                winBefore: 70, winAfter: 10, betterSan: "Nf3", bestUCI: nil),
        ]
        let game = savedGame(plyCount: 10, moveRecords: records)

        let record = try #require(HistoryStore().buildGameRecord(from: game, identity: PlayerIdentity()))
        #expect(record.mistakes.count == 1)
        #expect(record.mistakes.first?.motifs.isEmpty == true)
        #expect(record.mistakes.first?.bestUci == nil)
    }

    @Test("playerIsWhite == false produces reviewedSide/playerResult matching Black's result")
    func blackSideResult() throws {
        let game = savedGame(
            playerIsWhite: false, plyCount: 10,
            resultText: "Checkmate — you win! 🎉", moveRecords: [])

        let record = try #require(HistoryStore().buildGameRecord(from: game, identity: PlayerIdentity()))
        #expect(record.reviewedSide == "black")
        #expect(record.playerResult == "win")
        // Black won, so the PGN-style result must read "0-1", not White's "1-0".
        #expect(record.result == "0-1")
    }

    @Test("a move made with few pieces left on the board classifies as endgame")
    func endgamePhase() throws {
        // King + rook only for each side -- well under the <= 6 non-king/non-pawn
        // piece cutoff `HistoryStore.phase` already uses.
        let endgameFEN = "4k3/8/8/8/8/8/8/4K2R w K - 0 40"
        let records = [
            CoachPromptBuilder.PlayMoveRecord(
                moveNumber: 40, san: "Rh8", classification: "mistake",
                winBefore: 60, winAfter: 48, betterSan: "Kd2", bestUCI: nil),
        ]
        let game = savedGame(plyCount: 10, moveRecords: records, fenOverrides: [0: endgameFEN])

        let record = try #require(HistoryStore().buildGameRecord(from: game, identity: PlayerIdentity()))
        #expect(record.mistakes.first?.phase == "endgame")
    }
}
