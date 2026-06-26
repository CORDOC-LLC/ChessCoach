//  BoardGeometryTests.swift
//  U2 — board coordinate geometry: file/rank → Square mapping and the
//  orientation-aware display mapping used to place pieces and edge labels.
//  (Label contrast itself is verified visually on device.)

import Testing
import CoreGraphics
import ChessKit
@testable import GemmaChessCore

struct BoardGeometryTests {

    @Test func squareFromFileRank() {
        #expect(BoardGeometry.square(file: 1, rank: 1) == .a1)
        #expect(BoardGeometry.square(file: 5, rank: 4) == .e4)
        #expect(BoardGeometry.square(file: 8, rank: 8) == .h8)
        #expect(BoardGeometry.square(file: 0, rank: 1) == nil)
        #expect(BoardGeometry.square(file: 9, rank: 1) == nil)
        #expect(BoardGeometry.square(file: 1, rank: 9) == nil)
    }

    @Test func squareFromNotation() {
        #expect(BoardGeometry.square("a1") == .a1)
        #expect(BoardGeometry.square("E4") == .e4)
        #expect(BoardGeometry.square("z9") == nil)
        #expect(BoardGeometry.square("a") == nil)
    }

    // The display mapping: `square(atPoint:)` is the inverse of `center(...)`, so a
    // round-trip through both must recover the square, and a1 lands bottom-left when
    // white is at the bottom and top-right when black is.
    @Test func orientationMappingWhiteAtBottom() {
        let side: CGFloat = 800
        let a1 = BoardGeometry.center(.a1, side: side, whiteAtBottom: true)
        // a1 bottom-left: small x, large y.
        #expect(a1.x < side / 2)
        #expect(a1.y > side / 2)
        #expect(BoardGeometry.square(atPoint: a1, side: side, whiteAtBottom: true) == .a1)
        let h8 = BoardGeometry.center(.h8, side: side, whiteAtBottom: true)
        #expect(h8.x > side / 2)
        #expect(h8.y < side / 2)
        #expect(BoardGeometry.square(atPoint: h8, side: side, whiteAtBottom: true) == .h8)
    }

    @Test func orientationMappingBlackAtBottom() {
        let side: CGFloat = 800
        let a1 = BoardGeometry.center(.a1, side: side, whiteAtBottom: false)
        // a1 flips to top-right when black is at the bottom.
        #expect(a1.x > side / 2)
        #expect(a1.y < side / 2)
        #expect(BoardGeometry.square(atPoint: a1, side: side, whiteAtBottom: false) == .a1)
    }
}
