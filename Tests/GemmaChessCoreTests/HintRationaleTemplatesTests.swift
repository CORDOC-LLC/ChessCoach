//  HintRationaleTemplatesTests.swift
//  U3 — the free, template-based hint "why". Pure, engine-free classification over a
//  FEN + a UCI move (+ an optional already-known mate distance), so these tests never
//  touch Stockfish: every FEN below is hand-constructed to exercise one classification.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@Suite("HintRationaleTemplates")
struct HintRationaleTemplatesTests {

    // MARK: Capture

    @Test func captureNamesTheCapturedPiece() {
        // White rook a1, black queen e1 undefended, black king e8.
        let fen = "4k3/8/8/8/8/8/8/R3q2K w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "a1e1")
        #expect(text.contains("queen"))
        #expect(text.lowercased().contains("wins"))
    }

    @Test func enPassantCaptureIsRecognizedAsWinningAPawn() {
        // White pawn e5, black just played d7-d5 (en passant target d6), black king e8, white king e1.
        let fen = "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "d5e6")
        #expect(text.contains("pawn"))
    }

    // MARK: Mate

    @Test func mateInOneUsesCheckmateTemplate() {
        let fen = "6k1/8/8/8/8/8/8/R5K1 w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "a1a8", mateIn: 1)
        #expect(text == "Delivers checkmate.")
    }

    @Test func mateInTwoPlusUsesSetsUpMateTemplate() {
        let fen = "6k1/8/8/8/8/8/8/R5K1 w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "a1a7", mateIn: 3)
        #expect(text.contains("mate in 3"))
    }

    @Test func mateInParsesPositiveMateEvalStrings() {
        #expect(HintRationaleTemplates.mateIn(fromEval: "#1") == 1)
        #expect(HintRationaleTemplates.mateIn(fromEval: "#4") == 4)
    }

    @Test func mateInIgnoresMateAgainstTheSideToMove() {
        // "#-N" means the side to move gets mated -- never a reason to praise their move.
        #expect(HintRationaleTemplates.mateIn(fromEval: "#-2") == nil)
    }

    @Test func mateInIgnoresNonMateEvals() {
        #expect(HintRationaleTemplates.mateIn(fromEval: "+1.25") == nil)
        #expect(HintRationaleTemplates.mateIn(fromEval: "-0.40") == nil)
    }

    // MARK: Fallback (quiet developing move)

    @Test func quietDevelopingMoveUsesFallbackTemplate() {
        let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: start, moveUCI: "g1f3")
        #expect(!text.isEmpty)
        #expect(!text.contains("Wins"))
        #expect(!text.lowercased().contains("mate"))
    }

    // MARK: Priority order — capture beats "defensive" when both apply

    @Test func captureTakesPriorityOverDefensiveClassification() {
        // White knight e4 is hanging to the black pawn on d5 (undefended), but the
        // move captures a black knight on f6 -- capture must win per the documented
        // priority order (mate > capture > defensive > fallback).
        let fen = "7k/8/5n2/3p4/4N3/8/8/7K w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "e4f6")
        #expect(text.contains("knight"))
        #expect(text.lowercased().contains("wins"))
    }

    @Test func mateTakesPriorityOverCapture() {
        // Same capturing move as above, but a mate distance is already known --
        // mate must win per the documented priority order.
        let fen = "7k/8/5n2/3p4/4N3/8/8/7K w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "e4f6", mateIn: 2)
        #expect(text.contains("mate in 2"))
        #expect(!text.lowercased().contains("wins"))
    }

    // MARK: Defensive (escapes a hanging piece, no capture)

    @Test func escapingAHangingPieceUsesDefensiveTemplate() {
        // White knight e4, attacked by an undefended black pawn on d5, escapes to a
        // square the same hanging check no longer flags.
        let fen = "7k/8/8/3p4/4N3/8/8/7K w - - 0 1"
        let text = HintRationaleTemplates.rationale(fenBefore: fen, moveUCI: "e4g5")
        #expect(text.contains("danger") || text.contains("Gets"))
    }

    // MARK: Never crashes on malformed input

    @Test func malformedUCIFallsBackToGenericTemplate() {
        let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        for bad in ["", "zz", "e9e9", "abcdefgh"] {
            let text = HintRationaleTemplates.rationale(fenBefore: start, moveUCI: bad)
            #expect(!text.isEmpty)
        }
    }

    @Test func malformedFENFallsBackToGenericTemplate() {
        let text = HintRationaleTemplates.rationale(fenBefore: "not a fen", moveUCI: "e2e4")
        #expect(!text.isEmpty)
    }
}
