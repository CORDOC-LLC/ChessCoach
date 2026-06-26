//  ReviewSessionTests.swift
//  U8 — session model. Engine-free: builds sessions by hand to test Codable, navigation,
//  opening resolution, and the summary payload.

import Foundation
import Testing
@testable import GemmaChessCore

struct ReviewSessionTests {

    static func sampleMistake(ply: Int) -> MoveReview {
        MoveReview(
            ply: ply, moveNumber: (ply + 1) / 2, color: ply % 2 == 1 ? "white" : "black",
            moveSAN: "g4", moveUCI: "g2g4",
            fenBefore: "rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2",
            fenAfter: "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2",
            evalBefore: 20, evalAfter: -9999,
            winBefore: 50, winAfter: 0, winSwing: 50,
            classification: "blunder", bestMoveSAN: "d4", bestLineUCI: ["d2d4"], bestLineSAN: ["d4"],
            accuracy: 0, comment: "Win chance 50.0% → 0.0%.")
    }

    static func sampleSession() -> ReviewSession {
        let m = sampleMistake(ply: 3)
        return ReviewSession(
            pgn: "1. f3 e5 2. g4 Qh4# 0-1",
            player: "white",
            headers: ["White": "tester", "Black": "opponent", "Result": "0-1", "TimeControl": "300+0"],
            result: "0-1",
            speed: "blitz",
            accuracyWhite: 12.3,
            accuracyBlack: 99.1,
            allMoves: [m],
            mistakes: [m],
            currentIndex: 0,
            thresholds: [5, 10, 15],
            sweepDepth: 16,
            timeline: [
                TimelineNode(node: 0, fen: "start", winWhite: 50, color: "white", moveNumber: 1,
                             ply: 1, moveSAN: "f3", moveUCI: "f2f3"),
                TimelineNode(node: 1, fen: "mid", winWhite: 48, color: "black", moveNumber: 1),
            ])
    }

    @Test("Codable round-trip preserves the session")
    func codableRoundTrip() throws {
        let original = Self.sampleSession()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewSession.self, from: data)
        #expect(decoded == original)
    }

    @Test("gotoMistake clamps and validates")
    func gotoMistake() {
        var sess = Self.sampleSession()
        let hit = sess.gotoMistake(0)
        #expect(hit != nil)
        #expect(hit?.review.classification == "blunder")
        #expect(sess.currentIndex == 0)
        // Out of range -> nil, index unchanged.
        #expect(sess.gotoMistake(5) == nil)
        #expect(sess.gotoMistake(-1) == nil)
    }

    @Test("gotoMistake on a session with no mistakes returns nil")
    func gotoMistakeEmpty() {
        var sess = Self.sampleSession()
        sess.mistakes = []
        #expect(sess.gotoMistake(0) == nil)
    }

    @Test("resolveOpening prefers the Opening header")
    func resolveOpeningHeader() {
        var sess = Self.sampleSession()
        sess.headers["Opening"] = "King's Gambit"
        #expect(sess.resolveOpening() == "King's Gambit")
    }

    @Test("resolveOpening falls back to a local lookup over the timeline FENs (Italian game)")
    func resolveOpeningFromFens() throws {
        // The Italian game from multi.pgn, headers stripped of any Opening tag.
        let url = try #require(
            Bundle.module.url(forResource: "multi", withExtension: "pgn", subdirectory: "Fixtures/pgns"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let italianPGN = MultiPGN.splitPGN(text)[0]
        let fens = try #require(ChessLogic.fens(forPGN: italianPGN))
        var sess = Self.sampleSession()
        sess.headers["Opening"] = nil
        sess.timeline = fens.enumerated().map { (i, fen) in
            TimelineNode(node: i, fen: fen, winWhite: 50, color: "white", moveNumber: 1)
        }
        let opening = sess.resolveOpening()
        #expect(!opening.isEmpty)
    }

    @Test("summary carries mistakes, accuracy, opening and speed")
    func summary() {
        let sess = Self.sampleSession()
        let s = sess.summary()
        #expect(s.numMistakes == 1)
        #expect(s.mistakes.first?.classification == "blunder")
        #expect(s.mistakes.first?.nodeIndex == 2)  // ply 3 -> node 2
        #expect(s.accuracyWhite == 12.3)
        #expect(s.speed == "blitz")
        #expect(s.white == "tester")
    }
}
