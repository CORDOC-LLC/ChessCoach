//  CapturedTrayFlashTests.swift
//  Covers which piece the captured tray flashes when its contents change. The
//  animation itself isn't asserted -- only the pure index diff that decides
//  whether anything flashes at all, and which glyph.

import Testing
@testable import GemmaChessCore

@Suite("CapturedTrayView capture flash")
struct CapturedTrayFlashTests {
    @Test("a piece appended to an empty tray flashes")
    func firstCapture() {
        #expect(CapturedTrayView.addedIndex(from: [], to: ["p"]) == 0)
    }

    @Test("the added piece flashes wherever value-sorting placed it")
    func insertionInTheMiddle() {
        // A rook capture lands ahead of the pawns in the value-sorted row.
        #expect(CapturedTrayView.addedIndex(from: ["p", "p"], to: ["r", "p", "p"]) == 0)
        #expect(CapturedTrayView.addedIndex(from: ["q", "p"], to: ["q", "n", "p"]) == 1)
    }

    @Test("a take-back removes a piece and flashes nothing")
    func removalDoesNotFlash() {
        #expect(CapturedTrayView.addedIndex(from: ["r", "p"], to: ["p"]) == nil)
        #expect(CapturedTrayView.addedIndex(from: ["p"], to: []) == nil)
    }

    @Test("an unchanged tray flashes nothing")
    func noChangeDoesNotFlash() {
        #expect(CapturedTrayView.addedIndex(from: ["r", "p"], to: ["r", "p"]) == nil)
        #expect(CapturedTrayView.addedIndex(from: [], to: []) == nil)
    }

    @Test("a duplicate glyph flashes the newly-vacant slot, not an existing one")
    func duplicateOfAnExistingKind() {
        // Three pawns where there were two: the diff consumes both old pawns
        // first, so the flash lands on the trailing copy.
        #expect(CapturedTrayView.addedIndex(from: ["p", "p"], to: ["p", "p", "p"]) == 2)
    }
}
