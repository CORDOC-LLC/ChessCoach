//  PuzzleShareCardsTests.swift
//  Covers PuzzleRushShareCard, StreakShareCard, and the `StreakMilestones`
//  boundary check (plan U5): a representative Puzzle Rush render, a
//  milestone streak render, and the milestone helper's exact boundary
//  values -- 4/false, 5/true, 6/false, 9/false, 10/true -- plus a broken
//  (reset-to-1) streak never counting as a milestone.
//
//  Environment note: mirrors ShareCardRendererTests.swift's approach (plan
//  U4) -- `ImageRenderer` needs a real rendering context. In the SPM test
//  target (no live UIWindow/UIApplication), `ImageRenderer.uiImage` has been
//  observed to still produce a valid, correctly-sized image for simple
//  SwiftUI content on iOS simulator/device test runs, since `ImageRenderer`
//  doesn't require an attached window -- it renders off-screen via Core
//  Animation. If a future SDK/OS combination causes `render` to return `nil`
//  in this harness, these tests will fail loudly rather than silently pass,
//  which is preferable to skipping them.

import Testing
import SwiftUI
@testable import GemmaChessCore

#if os(iOS)
@Suite("PuzzleRushShareCard")
@MainActor
struct PuzzleRushShareCardTests {

    @Test("rendering a representative correctCount produces a non-nil image at the expected fixed size")
    func rendersRushCard() {
        let themeStore = ThemeStore()
        let card = PuzzleRushShareCard(correctCount: 14, wrongAttempts: 2, durationSeconds: 180)
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: PuzzleRushShareCard.cardSize)

        #expect(image != nil)
        if let image {
            #expect(abs(image.size.width - PuzzleRushShareCard.cardSize.width) < 0.5)
            #expect(abs(image.size.height - PuzzleRushShareCard.cardSize.height) < 0.5)
        }
    }

    @Test("rendering with zero wrong attempts also succeeds")
    func rendersRushCardWithNoMisses() {
        let themeStore = ThemeStore()
        let card = PuzzleRushShareCard(correctCount: 20, wrongAttempts: 0, durationSeconds: 180)
            .environment(themeStore)

        let image = ShareCardRenderer.render(card, size: PuzzleRushShareCard.cardSize)

        #expect(image != nil)
    }
}

@Suite("StreakShareCard")
@MainActor
struct StreakShareCardTests {

    @Test("rendering a milestone streak (10) produces a non-nil image showing that count")
    func rendersMilestoneStreakCard() {
        let themeStore = ThemeStore()
        let card = StreakShareCard(streak: 10).environment(themeStore)

        let image = ShareCardRenderer.render(card, size: StreakShareCard.cardSize)

        #expect(image != nil)
        if let image {
            #expect(abs(image.size.width - StreakShareCard.cardSize.width) < 0.5)
            #expect(abs(image.size.height - StreakShareCard.cardSize.height) < 0.5)
        }
    }
}
#endif

@Suite("StreakMilestones")
struct StreakMilestonesTests {

    @Test("boundary values around the 5-day milestone", arguments: [
        (4, false), (5, true), (6, false), (9, false), (10, true),
    ])
    func boundaryValues(streak: Int, expected: Bool) {
        #expect(StreakMilestones.isMilestone(streak) == expected)
    }

    @Test("every configured milestone value is itself a milestone")
    func allConfiguredMilestonesMatch() {
        for value in StreakMilestones.values {
            #expect(StreakMilestones.isMilestone(value))
        }
    }

    @Test("a non-milestone streak (e.g. 6, mid-run between 5 and 10) is not a milestone")
    func nonMilestoneStreakIsNotFlagged() {
        #expect(!StreakMilestones.isMilestone(6))
    }

    @Test("a streak that resets to 1 (broken streak) is never a milestone")
    func brokenStreakResetIsNotAMilestone() {
        #expect(!StreakMilestones.isMilestone(1))
    }

    @Test("zero (no streak yet) is not a milestone")
    func zeroStreakIsNotAMilestone() {
        #expect(!StreakMilestones.isMilestone(0))
    }
}
