//  ChessLogicTests.swift
//  Exercises the ChessKit facade: FEN round-trips, EPD stability, legal-move
//  generation (incl. check), SAN <-> UCI, PV replay, and move application.

import Testing
import ChessKit
@testable import GemmaChessCore

struct ChessLogicTests {

    static let standard = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    /// Position after 1.e4 (Black to move).
    static let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

    @Test func fenRoundTrip() {
        #expect(ChessLogic.isValidFEN(Self.standard))
        #expect(ChessLogic.normalizedFEN(Self.standard) == Self.standard)
        #expect(!ChessLogic.isValidFEN("not a fen"))
        #expect(ChessLogic.normalizedFEN("garbage") == nil)
    }

    @Test func epdDropsMoveCounters() {
        let a = ChessLogic.epd(fromFEN: Self.standard)
        let b = ChessLogic.epd(fromFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 17 42")
        #expect(a == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -")
        #expect(a == b)  // same position, different counters -> same EPD
        #expect(ChessLogic.epd(fromFEN: "too few fields") == nil)
    }

    @Test func legalDestinationsMidgame() {
        let dests = ChessLogic.legalDestinations(forFEN: Self.afterE4)
        // Black to move: the g8 knight can reach f6 and h6.
        let knight = dests[.g8]
        #expect(knight?.contains(.f6) == true)
        #expect(knight?.contains(.h6) == true)
        // White pieces (idle side) are not included.
        #expect(dests[.e4] == nil)
        #expect(ChessLogic.sideToMove(forFEN: Self.afterE4) == .black)
    }

    @Test func legalDestinationsInCheck() {
        // Black king on e8 is checked by the white queen on e2 down the open e-file.
        // (A queen is on the board, so this isn't an insufficient-material draw.)
        let checkFEN = "4k3/8/8/8/8/8/4Q3/4K3 b - - 0 1"
        #expect(ChessLogic.isCheck(forFEN: checkFEN))
        let dests = ChessLogic.legalDestinations(forFEN: checkFEN)
        // The king must have escape squares but cannot stay on the e-file.
        let king = dests[.e8] ?? []
        #expect(!king.isEmpty)
        #expect(!king.contains(.e7))  // still on the checking file
        #expect(!ChessLogic.isCheck(forFEN: Self.standard))
    }

    @Test func sanToUciAndBack() {
        #expect(ChessLogic.uci(fromSAN: "e4", inFEN: Self.standard) == "e2e4")
        #expect(ChessLogic.uci(fromSAN: "Nf3", inFEN: Self.standard) == "g1f3")
        #expect(ChessLogic.san(fromUCI: "e2e4", inFEN: Self.standard) == "e4")
        #expect(ChessLogic.san(fromUCI: "g1f3", inFEN: Self.standard) == "Nf3")
        #expect(ChessLogic.uci(fromSAN: "Zz9", inFEN: Self.standard) == nil)
    }

    @Test func pvReplayToSAN() {
        let pv = ["e2e4", "e7e5", "g1f3", "b8c6"]
        #expect(ChessLogic.pvToSAN(pv, fromFEN: Self.standard) == ["e4", "e5", "Nf3", "Nc6"])
        // maxMoves caps the output length.
        #expect(ChessLogic.pvToSAN(pv, fromFEN: Self.standard, maxMoves: 2) == ["e4", "e5"])
    }

    @Test func applyMoveToFEN() {
        // SAN and UCI yield the same resulting position.
        let viaSAN = ChessLogic.fen(afterMove: "e4", fromFEN: Self.standard)
        let viaUCI = ChessLogic.fen(afterMove: "e2e4", fromFEN: Self.standard)
        #expect(viaSAN != nil)
        #expect(viaSAN == viaUCI)
        #expect(ChessLogic.sideToMove(forFEN: viaSAN!) == .black)
        #expect(ChessLogic.epd(fromFEN: viaSAN!)?.hasPrefix("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b") == true)
        // Illegal move -> nil.
        #expect(ChessLogic.fen(afterMove: "e5", fromFEN: Self.standard) == nil)
    }

    @Test func pgnReplayFens() {
        let pgn = "1. e4 e5 2. Nf3"
        let fens = ChessLogic.fens(forPGN: pgn)
        #expect(fens?.count == 3)  // one FEN per ply, starting position excluded
        #expect(ChessLogic.finalFEN(forPGN: pgn) == fens?.last)
    }

    @Test func noCheckAttackersInAQuietPosition() {
        #expect(ChessLogic.checkAttackers(forFEN: Self.standard) == nil)
    }

    @Test("checkAttackers finds the single attacker + king square for Fool's Mate")
    func checkAttackersOnCheckmate() throws {
        // 1. f3 e5 2. g4 Qh4# -- the queen on h4 mates the king on e1 along the
        // h4-e1 diagonal; nothing else attacks e1.
        let foolsMate = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
        #expect(ChessLogic.status(forFEN: foolsMate) == .checkmate)

        let info = try #require(ChessLogic.checkAttackers(forFEN: foolsMate))
        #expect(info.king == Square("e1"))
        #expect(info.attackers == [Square("h4")])
    }

    @Test("checkAttackers also works for check-but-not-mate")
    func checkAttackersOnPlainCheck() throws {
        let fen = "4k3/8/8/8/8/8/8/4R2K b - - 0 1"   // rook checks along the e-file
        #expect(ChessLogic.status(forFEN: fen) == .check)

        let info = try #require(ChessLogic.checkAttackers(forFEN: fen))
        #expect(info.king == Square("e8"))
        #expect(info.attackers == [Square("e1")])
    }
}
