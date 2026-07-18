//  FENBoardEditorTests.swift

import Testing
import ChessKit
@testable import GemmaChessCore

@Suite("FENBoardEditor")
struct FENBoardEditorTests {

    private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    @Test("placing a piece on an empty square adds it without disturbing the rest of the rank")
    func placeOnEmptySquare() {
        let result = FENBoardEditor.settingSquare(Square("e4"), to: (.queen, .white), inFEN: startFEN)
        #expect(result == "rnbqkbnr/pppppppp/8/8/4Q3/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }

    @Test("replacing an occupied square swaps the piece")
    func replaceOccupiedSquare() {
        let result = FENBoardEditor.settingSquare(Square("e1"), to: (.queen, .black), inFEN: startFEN)
        #expect(result == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQqBNR w KQkq - 0 1")
    }

    @Test("clearing a square (nil piece) empties it")
    func clearSquare() {
        let result = FENBoardEditor.settingSquare(Square("a1"), to: nil, inFEN: startFEN)
        #expect(result == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NBQKBNR w KQkq - 0 1")
    }

    @Test("fields after piece placement (side to move, castling, etc.) are preserved untouched")
    func preservesOtherFields() {
        let fen = "8/8/8/8/8/8/8/8 b Kq e3 4 12"
        let result = FENBoardEditor.settingSquare(Square("d4"), to: (.knight, .black), inFEN: fen)
        #expect(result == "8/8/8/8/3n4/8/8/8 b Kq e3 4 12")
    }

    @Test("piece(at:) reads occupied and empty squares correctly")
    func pieceAtSquare() {
        let e1 = FENBoardEditor.piece(at: Square("e1"), inFEN: startFEN)
        #expect(e1?.kind == .king && e1?.color == .white)
        let d8 = FENBoardEditor.piece(at: Square("d8"), inFEN: startFEN)
        #expect(d8?.kind == .queen && d8?.color == .black)
        #expect(FENBoardEditor.piece(at: Square("e4"), inFEN: startFEN) == nil)
    }

    @Test("moving a piece = clear source + set destination")
    func movePieceViaTwoEdits() {
        guard let knight = FENBoardEditor.piece(at: Square("g1"), inFEN: startFEN) else {
            Issue.record("expected a knight on g1")
            return
        }
        var fen = FENBoardEditor.settingSquare(Square("g1"), to: nil, inFEN: startFEN)
        fen = FENBoardEditor.settingSquare(Square("f3"), to: knight, inFEN: fen)
        #expect(fen == "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1")
    }

    @Test("rotating the start position 180° swaps the armies' halves and mirrors files")
    func rotate180StartPosition() {
        let rotated = FENBoardEditor.rotated180(fen: startFEN)
        #expect(rotated == "RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr w - - 0 1")
        // Rotating twice restores placement (castling/ep stay cleared).
        let twice = FENBoardEditor.rotated180(fen: rotated)
        #expect(twice == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1")
    }

    @Test("rotation clears castling and en passant but keeps side to move and counters")
    func rotationClearsRights() {
        let fen = "8/8/8/8/3P4/8/8/8 b KQkq e3 4 12"
        let rotated = FENBoardEditor.rotated180(fen: fen)
        #expect(rotated == "8/8/8/4P3/8/8/8/8 b - - 4 12")
    }

    @Test("looksRotated flags an upside-down scan and passes a normal one")
    func detectsRotation() {
        #expect(!FENBoardEditor.looksRotated(fen: startFEN))
        #expect(FENBoardEditor.looksRotated(fen: FENBoardEditor.rotated180(fen: startFEN)))
        // Kings only, same rank: no clear separation, don't second-guess.
        #expect(!FENBoardEditor.looksRotated(fen: "8/8/8/3kK3/8/8/8/8 w - - 0 1"))
    }

    @Test("a round trip of place-then-clear returns to the original FEN")
    func placeThenClearRoundTrips() {
        let placed = FENBoardEditor.settingSquare(Square("h8"), to: (.rook, .white), inFEN: startFEN)
        let cleared = FENBoardEditor.settingSquare(Square("h8"), to: nil, inFEN: placed)
        #expect(cleared == "rnbqkbn1/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }
}
