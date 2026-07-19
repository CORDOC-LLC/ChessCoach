//  WeaknessReportStoreTests.swift
//  Covers WeaknessReportStore's cache/refresh-gate state (plan U5): no
//  cached report always allows generation, a cached report only allows
//  refresh once enough new games have accumulated, and the cache round-trips
//  the narrative/timestamp correctly.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("WeaknessReportStore")
struct WeaknessReportStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "WeaknessReportStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("no cached report yet -> generation is always allowed")
    func noCacheAlwaysAllowsGeneration() {
        let d = freshDefaults()
        #expect(WeaknessReportStore.canRefresh(currentGameCount: 0, defaults: d))
        #expect(WeaknessReportStore.canRefresh(currentGameCount: 100, defaults: d))
    }

    @Test("cached report with fewer than the threshold's worth of new games -> refresh disabled")
    func belowThresholdDisablesRefresh() {
        let d = freshDefaults()
        WeaknessReportStore.recordGenerated(narrative: "You tend to miss forks.", gameCount: 10, defaults: d)

        #expect(!WeaknessReportStore.canRefresh(currentGameCount: 12, defaults: d))
    }

    @Test("cached report with at least the threshold's worth of new games -> refresh enabled")
    func atOrAboveThresholdEnablesRefresh() {
        let d = freshDefaults()
        WeaknessReportStore.recordGenerated(narrative: "You tend to miss forks.", gameCount: 10, defaults: d)

        #expect(WeaknessReportStore.canRefresh(
            currentGameCount: 10 + WeaknessReportStore.refreshGameThreshold, defaults: d))
    }

    @Test("cache round-trips the narrative and generation timestamp")
    func cacheRoundTrips() {
        let d = freshDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        WeaknessReportStore.recordGenerated(narrative: "You tend to miss forks.", gameCount: 5, now: now, defaults: d)

        #expect(WeaknessReportStore.cachedNarrative(defaults: d) == "You tend to miss forks.")
        #expect(WeaknessReportStore.generatedAt(defaults: d) == now)
    }

    @Test("reset clears all cached state")
    func resetClearsState() {
        let d = freshDefaults()
        WeaknessReportStore.recordGenerated(narrative: "You tend to miss forks.", gameCount: 5, defaults: d)

        WeaknessReportStore.reset(defaults: d)

        #expect(WeaknessReportStore.cachedNarrative(defaults: d) == nil)
        #expect(WeaknessReportStore.generatedAt(defaults: d) == nil)
        #expect(WeaknessReportStore.canRefresh(currentGameCount: 0, defaults: d))
    }
}
