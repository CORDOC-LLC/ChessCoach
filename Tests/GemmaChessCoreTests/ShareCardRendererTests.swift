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

    // MARK: Summary builders
    //
    // The card now takes a `GameShareSummary` rather than loose strings, so
    // these build one from plain values -- still no view model, still no engine.

    private static let midFEN = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

    private func summary(
        outcome: PlayOutcome,
        openingName: String? = "Italian Game",
        records: [CoachPromptBuilder.PlayMoveRecord] = [
            .init(moveNumber: 1, san: "e4", classification: "best",
                  winBefore: 50, winAfter: 50, betterSan: nil, bestUCI: "e2e4", fen: midFEN)
        ]
    ) -> GameShareSummary {
        GameShareSummary.make(
            moveRecords: records,
            finalFEN: Self.midFEN,
            playerIsWhite: true,
            lastMove: nil,
            terminalExplanation: nil,
            openingName: openingName,
            outcome: outcome,
            isResignation: false,
            stats: PlayStats(wins: 1, losses: 2, draws: 0)
        )
    }

    @Test("rendering a win result produces a non-nil image at the expected fixed size")
    func rendersWinCard() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(summary: summary(outcome: .win))
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
        let card = GameResultShareCard(summary: summary(outcome: .loss, openingName: nil))
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
    }

    @Test("rendering a draw result succeeds")
    func rendersDrawCard() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(summary: summary(outcome: .draw, openingName: "Caro-Kann Defense"))
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
    }

    @Test("an unusually long opening name or result string does not crash the render pass")
    func rendersWithLongStrings() {
        let themeStore = ThemeStore()
        let longOpening = String(repeating: "Extremely Elaborate Opening Name With Many Words ", count: 12)
        let card = GameResultShareCard(summary: summary(outcome: .win, openingName: longOpening))
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize)

        #expect(image != nil)
        if let image {
            #expect(abs(image.size.width - GameResultShareCard.cardSize.width) < 0.5)
            #expect(abs(image.size.height - GameResultShareCard.cardSize.height) < 0.5)
        }
    }

    @Test("a game with no graded moves renders without a fabricated accuracy")
    func rendersWithNoGradedMoves() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(summary: summary(outcome: .loss, records: []))
            .environment(themeStore)

        #expect(ShareCardRenderer.render(card, size: GameResultShareCard.cardSize) != nil)
    }

    @Test("the card renders at the shared 4:5 size every share card now uses")
    func rendersAtSharedFourFiveSize() {
        #expect(GameResultShareCard.cardSize == ShareCard.size)
        #expect(PuzzleRushShareCard.cardSize == ShareCard.size)
        #expect(StreakShareCard.cardSize == ShareCard.size)
        // 4:5 -- 1080x1350 once rendered at 3x.
        let ratio = ShareCard.size.width / ShareCard.size.height
        #expect(abs(ratio - 0.8) < 0.001)
    }

    @Test("an invalid (zero) size fails soft and returns nil, never crashes")
    func invalidSizeReturnsNil() {
        let themeStore = ThemeStore()
        let card = GameResultShareCard(summary: summary(outcome: .draw, openingName: nil))
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: .zero)

        #expect(image == nil)
    }
}
#endif
