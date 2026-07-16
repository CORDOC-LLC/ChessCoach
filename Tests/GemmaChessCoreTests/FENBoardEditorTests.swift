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

    @Test("a round trip of place-then-clear returns to the original FEN")
    func placeThenClearRoundTrips() {
        let placed = FENBoardEditor.settingSquare(Square("h8"), to: (.rook, .white), inFEN: startFEN)
        let cleared = FENBoardEditor.settingSquare(Square("h8"), to: nil, inFEN: placed)
        #expect(cleared == "rnbqkbn1/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }
}
