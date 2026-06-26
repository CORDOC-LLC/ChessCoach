//  MultiPGNTests.swift
//  Multi-game PGN splitting (lossless, with clk comments preserved), malformed
//  chunk rejection, and uploader-handle detection.

import Foundation
import Testing
@testable import GemmaChessCore

struct MultiPGNTests {

    /// The bundled two-game fixture text.
    static func fixtureText() throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "multi", withExtension: "pgn", subdirectory: "Fixtures/pgns")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func splitsTwoGamesPreservingClocks() throws {
        let games = MultiPGN.splitPGN(try Self.fixtureText())
        #expect(games.count == 2)
        // The original [%clk] comments survive the split.
        #expect(games[0].contains("[%clk 0:10:00]"))
        #expect(games[0].contains("Event \"Fixture Multi A\""))
        #expect(games[1].contains("[%clk 0:03:00]"))
    }

    @Test func dropsMalformedChunk() {
        let good = """
        [Event "Good"]
        [White "a"]
        [Black "b"]
        [Result "1-0"]

        1. e4 e5 1-0
        """
        let malformed = """
        [Event "Bad"]
        [White "c"]
        [Black "d"]

        1. xx99 yy88
        """
        let games = MultiPGN.splitPGN(good + "\n\n" + malformed)
        #expect(games.count == 1)
        #expect(games[0].contains("Event \"Good\""))
    }

    @Test func emptyInputYieldsNoGames() {
        #expect(MultiPGN.splitPGN("").isEmpty)
        #expect(MultiPGN.splitPGN("   \n\n  ").isEmpty)
    }

    @Test func detectsCommonHandleInFixture() throws {
        let games = MultiPGN.splitPGN(try Self.fixtureText())
        // "tester" is White in game A and Black in game B — the only common handle.
        #expect(MultiPGN.detectSelfHandle(games: games) == "tester")
    }

    @Test func preferListBreaksTie() {
        let g1 = """
        [Event "1"]
        [White "Alpha"]
        [Black "Beta"]
        [Result "*"]

        1. e4 e5 *
        """
        let g2 = """
        [Event "2"]
        [White "Beta"]
        [Black "Alpha"]
        [Result "*"]

        1. d4 d5 *
        """
        // Both handles are common to both games -> ambiguous without a preference.
        #expect(MultiPGN.detectSelfHandle(games: [g1, g2]) == nil)
        // The prefer list resolves the tie (case-insensitive).
        #expect(MultiPGN.detectSelfHandle(games: [g1, g2], prefer: ["beta"]) == "Beta")
    }

    @Test func nilWhenNoCommonHandle() {
        let g1 = """
        [Event "1"]
        [White "a"]
        [Black "b"]
        [Result "*"]

        1. e4 e5 *
        """
        let g2 = """
        [Event "2"]
        [White "c"]
        [Black "d"]
        [Result "*"]

        1. d4 d5 *
        """
        #expect(MultiPGN.detectSelfHandle(games: [g1, g2]) == nil)
    }

    @Test func headersReadTagPairs() {
        let pgn = """
        [Event "Test"]
        [White "wp"]
        [Black "bp"]
        [Result "1-0"]

        1. e4 e5 1-0
        """
        let headers = MultiPGN.headers(ofPGN: pgn)
        #expect(headers["Event"] == "Test")
        #expect(headers["White"] == "wp")
        #expect(headers["Result"] == "1-0")
    }
}
