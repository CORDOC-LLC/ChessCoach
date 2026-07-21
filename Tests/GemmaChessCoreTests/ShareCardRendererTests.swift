//  ShareCardRendererTests.swift
//  Covers ShareCardRenderer + GameResultShareCard (plan U4 / KTD-4): a win
//  render, a loss/draw render, and an edge case with an unusually long
//  opening name -- the card's own layout must truncate/wrap rather than the
//  renderer crashing.
//
//  Environment note: `ImageRenderer` needs a real rendering context. In the
//  SPM test target (no live UIWindow/UIApplication), `ImageRenderer.uiImage`
//  has been observed to still produce a valid, correctly-sized image for
//  simple SwiftUI content on iOS simulator/device test runs, since
//  `ImageRenderer` doesn't require an attached window -- it renders
//  off-screen via Core Animation. If a future SDK/OS combination causes
//  `render` to return `nil` in this harness, these tests will fail loudly
//  rather than silently pass, which is preferable to skipping them.

import Testing
import SwiftUI
@testable import GemmaChessCore

#if os(iOS)
@Suite("ShareCardRenderer")
@MainActor
struct ShareCardRendererTests {

    @Test("rendering a win result produces a non-nil image at the expected fixed size")
    func rendersWinCard() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(resultText: "You won by checkmate", outcome: .win, openingName: "Italian Game")
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
        if let image {
            #expect(abs(image.size.width - GameResultShareCard.cardSize.width) < 0.5)
            #expect(abs(image.size.height - GameResultShareCard.cardSize.height) < 0.5)
        }
    }

    @Test("rendering a loss result succeeds")
    func rendersLossCard() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(resultText: "You lost by resignation", outcome: .loss, openingName: nil)
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
    }

    @Test("rendering a draw result succeeds")
    func rendersDrawCard() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(resultText: "Draw by stalemate", outcome: .draw, openingName: "Caro-Kann Defense")
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
    }

    @Test("an unusually long opening name or result string does not crash the render pass")
    func rendersWithLongStrings() {
        let themeStore = ThemeStore()
        let longOpening = String(repeating: "Extremely Elaborate Opening Name With Many Words ", count: 12)
        let longResult = String(repeating: "This is a very long result description string. ", count: 8)
        let card = GameResultShareCard(resultText: longResult, outcome: .win, openingName: longOpening)
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
        if let image {
            #expect(abs(image.size.width - GameResultShareCard.cardSize.width) < 0.5)
            #expect(abs(image.size.height - GameResultShareCard.cardSize.height) < 0.5)
        }
    }

    @Test("an invalid (zero) size fails soft and returns nil, never crashes")
    func invalidSizeReturnsNil() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(resultText: "Draw", outcome: .draw, openingName: nil)
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: .zero)

        #expect(image == nil)
    }
}
#endif
