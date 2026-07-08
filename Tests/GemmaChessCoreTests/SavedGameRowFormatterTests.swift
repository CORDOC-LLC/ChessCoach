//  SavedGameRowFormatterTests.swift
//  Pure formatting for one row in the "My Games" list.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("SavedGameRowFormatter")
struct SavedGameRowFormatterTests {

    private func game(
        playerIsWhite: Bool = true, skill: Int = 6, isGameOver: Bool = false,
        resultText: String? = nil, openingName: String? = nil
    ) -> SavedGame {
        SavedGame(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
            playerIsWhite: playerIsWhite,
            startFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moves: [], sanMoves: [], fenHistory: ["rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"],
            skill: skill, isGameOver: isGameOver, resultText: resultText,
            openingName: openingName, openingECO: nil, moveNotes: [:], gameSummary: nil
        )
    }

    @Test("title names the side and engine skill")
    func titleFormat() {
        #expect(SavedGameRowFormatter.title(game(playerIsWhite: true, skill: 8))
                == "White vs Stockfish (skill 8)")
        #expect(SavedGameRowFormatter.title(game(playerIsWhite: false, skill: 3))
                == "Black vs Stockfish (skill 3)")
    }

    @Test("subtitle shows 'In progress' for an unfinished game")
    func subtitleInProgress() {
        #expect(SavedGameRowFormatter.subtitle(game(isGameOver: false)) == "In progress")
    }

    @Test("subtitle shows the result for a finished game")
    func subtitleFinished() {
        let subtitle = SavedGameRowFormatter.subtitle(
            game(isGameOver: true, resultText: "Checkmate — you win! 🎉"))
        #expect(subtitle == "Checkmate — you win! 🎉")
    }

    @Test("subtitle appends the opening name when known")
    func subtitleWithOpening() {
        let subtitle = SavedGameRowFormatter.subtitle(
            game(isGameOver: true, resultText: "Stalemate — it's a draw.", openingName: "London System"))
        #expect(subtitle == "Stalemate — it's a draw. · London System")
    }
}
