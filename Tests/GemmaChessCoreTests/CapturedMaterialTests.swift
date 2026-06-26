//  CapturedMaterialTests.swift
//  U3 — FEN-diff captured material: start has none, captures register correctly,
//  symmetric trades net to zero, and the promotion caveat is documented.

import Testing
@testable import GemmaChessCore

struct CapturedMaterialTests {

    static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    @Test func startPositionHasNoCaptures() {
        let c = CapturedMaterial.from(fen: Self.start)
        #expect(c.capturedByWhite.isEmpty)
        #expect(c.capturedByBlack.isEmpty)
        #expect(c.delta == 0)
    }

    @Test func whiteUpAKnight() {
        // Black is missing its b8 knight; everything else is standard.
        let fen = "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let c = CapturedMaterial.from(fen: fen)
        #expect(c.capturedByWhite == ["n"])   // White captured a black knight
        #expect(c.capturedByBlack.isEmpty)
        #expect(c.delta == 3)
    }

    @Test func mixedCapturesAndDelta() {
        // White missing a pawn (a2), Black missing a knight (b8) and a pawn (h7).
        let fen = "r1bqkbnr/ppppppp1/8/8/8/8/1PPPPPPP/RNBQKBNR w KQkq - 0 1"
        let c = CapturedMaterial.from(fen: fen)
        #expect(c.capturedByWhite.sorted() == ["n", "p"])   // White won N + P
        #expect(c.capturedByBlack == ["P"])                 // Black won a pawn
        // White: 3 + 1 = 4 won; Black: 1 won → delta +3.
        #expect(c.delta == 3)
    }

    @Test func symmetricTradeNetsZero() {
        // Each side missing one knight → even material.
        let fen = "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1"
        let c = CapturedMaterial.from(fen: fen)
        #expect(c.capturedByWhite == ["n"])
        #expect(c.capturedByBlack == ["N"])
        #expect(c.delta == 0)
    }

    @Test func capturedSortedByValueDescending() {
        // Black missing a queen and a pawn → queen should sort before pawn.
        let fen = "rnb1kbnr/ppppppp1/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let c = CapturedMaterial.from(fen: fen)
        #expect(c.capturedByWhite == ["q", "p"])
        #expect(c.delta == 10)
    }
}
