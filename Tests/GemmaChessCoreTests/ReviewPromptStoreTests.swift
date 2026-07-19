//  ReviewPromptStoreTests.swift
//  The review soft-ask trigger/cooldown/cap state machine, exercised with
//  fixed injected dates -- no reliance on wall-clock time.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("ReviewPromptStore")
struct ReviewPromptStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func date(_ offsetDays: Double, from base: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Date {
        base.addingTimeInterval(offsetDays * 24 * 60 * 60)
    }

    @Test("below both thresholds -> false")
    func belowBothThresholds() {
        let d = freshDefaults()
        let now = date(0)

        #expect(!ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold - 1,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold - 1,
            now: now,
            defaults: d
        ))
    }

    @Test("crossing only the lessons-completed threshold -> true")
    func lessonsThresholdOnly() {
        let d = freshDefaults()
        let now = date(0)

        #expect(ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold - 1,
            now: now,
            defaults: d
        ))
    }

    @Test("crossing only the games-played threshold -> true")
    func gamesThresholdOnly() {
        let d = freshDefaults()
        let now = date(0)

        #expect(ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold - 1,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: now,
            defaults: d
        ))
    }

    @Test("false immediately after recordShown(), same instant thresholds crossed")
    func falseImmediatelyAfterShown() {
        let d = freshDefaults()
        let now = date(0)

        #expect(ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: now,
            defaults: d
        ))

        ReviewPromptStore.recordShown(now: now, defaults: d)

        #expect(!ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: now,
            defaults: d
        ))
    }

    @Test("true again once the cooldown has fully elapsed")
    func trueAfterCooldownElapses() {
        let d = freshDefaults()
        let shownAt = date(0)
        ReviewPromptStore.recordShown(now: shownAt, defaults: d)

        let stillCoolingDown = shownAt.addingTimeInterval(ReviewPromptStore.cooldownInterval - 1)
        #expect(!ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: stillCoolingDown,
            defaults: d
        ))

        let afterCooldown = shownAt.addingTimeInterval(ReviewPromptStore.cooldownInterval + 1)
        #expect(ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: afterCooldown,
            defaults: d
        ))
    }

    @Test("permanently false once the show-count cap is reached")
    func permanentlyFalseAtCap() {
        let d = freshDefaults()
        var now = date(0)

        for _ in 0..<ReviewPromptStore.showCountCap {
            ReviewPromptStore.recordShown(now: now, defaults: d)
            now = now.addingTimeInterval(ReviewPromptStore.cooldownInterval + 1)
        }

        #expect(ReviewPromptStore.timesShown(defaults: d) == ReviewPromptStore.showCountCap)

        let farFuture = now.addingTimeInterval(365 * 24 * 60 * 60)
        #expect(!ReviewPromptStore.shouldPrompt(
            lessonsCompleted: ReviewPromptStore.lessonsCompletedThreshold,
            gamesPlayed: ReviewPromptStore.gamesPlayedThreshold,
            now: farFuture,
            defaults: d
        ))
    }

    @Test("fresh install, below threshold -> false, consistent with a fresh UserDefaults suite")
    func freshInstallBelowThreshold() {
        let d = freshDefaults()

        #expect(ReviewPromptStore.timesShown(defaults: d) == 0)
        #expect(ReviewPromptStore.lastShownDate(defaults: d) == nil)
        #expect(!ReviewPromptStore.shouldPrompt(
            lessonsCompleted: 0,
            gamesPlayed: 0,
            now: date(0),
            defaults: d
        ))
    }
}
