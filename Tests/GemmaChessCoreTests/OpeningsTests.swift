//  OpeningsTests.swift
//  ECO opening classification: a known line resolves to its ECO+name, the deepest
//  match wins over a shallower prefix, and unknown positions return nil.

import Testing
@testable import GemmaChessCore

struct OpeningsTests {

    /// Italian Game: 1.e4 e5 2.Nf3 Nc6 3.Bc4 (C50 in Resources/eco/c.tsv).
    static let italian = "1. e4 e5 2. Nf3 Nc6 3. Bc4"

    @Test func classifiesItalianGame() {
        let opening = Openings.classifyFromPgn(Self.italian)
        #expect(opening?.eco == "C50")
        #expect(opening?.name == "Italian Game")
    }

    @Test func deepestMatchWins() {
        let fens = ChessLogic.fens(forPGN: Self.italian)
        let allFens = try! #require(fens)
        let deep = Openings.classifyFromFens(allFens)
        // Classifying only through 1.e4 yields the shallow "King's Pawn Game".
        let shallow = Openings.classifyFromFens([allFens.first!])
        #expect(deep?.name == "Italian Game")
        #expect(shallow != nil)
        #expect(shallow?.name != deep?.name)  // deeper line is more specific
    }

    @Test func unknownPositionReturnsNil() {
        // A bare-kings endgame is not a named opening.
        #expect(Openings.classifyFromFens(["8/8/8/3k4/8/3K4/8/8 w - - 0 1"]) == nil)
        #expect(Openings.classifyFromFens([]) == nil)
    }

    @Test func singleFenMatch() {
        // The London System position after 1.d4 d5 2.Bf4 (D00) matches by one FEN;
        // a random non-book position doesn't. This is Play mode's live lookup.
        let london = try! #require(ChessLogic.finalFEN(forPGN: "1. d4 d5 2. Bf4"))
        let hit = Openings.match(fen: london)
        #expect(hit?.name.contains("London") == true)
        #expect(Openings.match(fen: "8/8/8/3k4/8/3K4/8/8 w - - 0 1") == nil)
    }

    @Test func bookLoadsEntries() {
        // Sanity: the vendored TSVs loaded into a non-trivial book.
        #expect(Openings.book.count > 1000)
    }
}
