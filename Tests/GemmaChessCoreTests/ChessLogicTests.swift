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

    // MARK: terminalExplanation

    @Test("Back-rank mate: own pawns block the forward steps, the rook covers the rank")
    func terminalExplanationBackRankMate() throws {
        // Black king g8 behind its own f7/g7/h7 pawns; white rook a8 mates along rank 8.
        let fen = "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1"
        #expect(ChessLogic.status(forFEN: fen) == .checkmate)

        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        #expect(e.reason == .checkmate)
        #expect(e.side == .black)
        #expect(e.kingSquare == Square("g8"))
        #expect(e.checkers == [Square("a8")])
        #expect(e.stuckPieces.isEmpty)

        // Forward steps: blocked by the mated side's own pawns.
        for name in ["f7", "g7", "h7"] {
            let flight = try #require(e.flightSquares.first { $0.square == Square(name) })
            #expect(flight.availability == .blockedByOwnPiece(.pawn))
        }
        // Along the rank: covered by the mating rook.
        let f8 = try #require(e.flightSquares.first { $0.square == Square("f8") })
        #expect(f8.availability == .covered(by: [Square("a8")]))
        #expect(e.flightSquares.count == 5)  // f7 g7 h7 f8 h8
    }

    @Test("X-ray: the square directly behind the king along the checker's line is unavailable")
    func terminalExplanationXRay() throws {
        // Black king e4 checked by the queen on e1. e5 is directly behind the king
        // along the checking file: `attackers(of:on:)` reports it as UNattacked,
        // because the king itself blocks the queen's ray. It is still not an escape.
        let fen = "8/8/8/7N/2P1k1P1/1N6/8/K3QB1B b - - 0 1"
        #expect(ChessLogic.status(forFEN: fen) == .checkmate)

        // Precondition: the naive query really is blind here.
        let position = try #require(Position(fen: fen))
        #expect(BoardAttacks.attackers(of: .white, on: Square("e5"), in: position).isEmpty)

        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        #expect(e.kingSquare == Square("e4"))
        let e5 = try #require(e.flightSquares.first { $0.square == Square("e5") })
        // Reported unavailable, and attributed to the x-raying checker.
        #expect(e5.availability == .covered(by: [Square("e1")]))
        // Every step of the king is accounted for; none is a real escape.
        #expect(e.flightSquares.count == 8)
    }

    @Test("Smothered mate: every step is blocked by the mated side's own pieces")
    func terminalExplanationSmotheredMate() throws {
        let fen = "6rk/5Npp/8/8/8/8/8/6K1 b - - 0 1"
        #expect(ChessLogic.status(forFEN: fen) == .checkmate)

        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        #expect(e.kingSquare == Square("h8"))
        #expect(e.checkers == [Square("f7")])
        #expect(e.flightSquares.count == 3)
        for flight in e.flightSquares {
            switch flight.availability {
            case .blockedByOwnPiece: break
            case .covered: Issue.record("\(flight.square.notation) should be own-blocked")
            }
        }
        let g8 = try #require(e.flightSquares.first { $0.square == Square("g8") })
        #expect(g8.availability == .blockedByOwnPiece(.rook))
    }

    @Test("A flight square covered by two enemy pieces names both")
    func terminalExplanationNamesEveryCoverer() throws {
        // Same back-rank mate, plus a bishop on b4 that also covers f8.
        let fen = "R5k1/5ppp/8/8/1B6/8/8/6K1 b - - 0 1"
        #expect(ChessLogic.status(forFEN: fen) == .checkmate)

        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        let f8 = try #require(e.flightSquares.first { $0.square == Square("f8") })
        guard case let .covered(by: coverers) = f8.availability else {
            Issue.record("f8 should be enemy-covered")
            return
        }
        #expect(Set(coverers) == Set([Square("a8"), Square("b4")]))
    }

    @Test("Stalemate returns the no-legal-move shape, with no king-trap geometry")
    func terminalExplanationStalemate() throws {
        let fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
        #expect(ChessLogic.status(forFEN: fen) == .stalemate)

        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        #expect(e.reason == .stalemate)
        #expect(e.side == .black)
        #expect(e.kingSquare == Square("h8"))
        #expect(e.checkers.isEmpty)          // the king is NOT reported as checked
        #expect(e.flightSquares.isEmpty)     // no king-trap geometry
        #expect(e.stuckPieces == [Square("h8")])
    }

    @Test("Non-terminal positions and bad FENs return nil")
    func terminalExplanationReturnsNilWhenNotApplicable() {
        #expect(ChessLogic.terminalExplanation(forFEN: Self.standard) == nil)
        // Plain check, not mate.
        #expect(ChessLogic.terminalExplanation(forFEN: "4k3/8/8/8/8/8/8/4R2K b - - 0 1") == nil)
        #expect(ChessLogic.terminalExplanation(forFEN: "not a fen") == nil)
        #expect(ChessLogic.terminalExplanation(forFEN: "") == nil)
    }

    // MARK: TerminalExplanationSummary (plan U2 / R10)

    @Test("Back-rank mate summarizes into a sentence naming blocked and covered squares")
    func summaryBackRankMate() throws {
        let fen = "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1"
        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        let text = try #require(TerminalExplanationSummary.text(for: e, fen: fen))

        #expect(text.hasPrefix("Checkmate."))
        #expect(text.contains("black king on g8"))
        #expect(text.contains("checked by the rook on a8"))
        #expect(text.contains("f7 blocked by Black's own pawn"))
        #expect(text.contains("f8 covered by the rook on a8"))
        #expect(text.hasSuffix("."))
    }

    @Test("Stalemate gets its own phrasing and never claims check")
    func summaryStalemate() throws {
        let fen = "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
        let e = try #require(ChessLogic.terminalExplanation(forFEN: fen))
        let text = try #require(TerminalExplanationSummary.text(for: e, fen: fen))

        #expect(text.hasPrefix("Stalemate."))
        #expect(text.contains("Black has no legal move"))
        #expect(text.contains("not in check"))
        #expect(!text.contains("no escape"))
    }

    @Test("No explanation summarizes to nil")
    func summaryNilExplanation() {
        #expect(TerminalExplanationSummary.text(for: nil, fen: "8/8/8/8/8/8/8/8 w - - 0 1") == nil)
    }
}
