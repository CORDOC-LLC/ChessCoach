//  PlayStatsStoreTests.swift
//  Lifetime win/loss/draw tally: starts at zero, records increment the right
//  bucket and return the updated tally, and reset clears everything.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("PlayStatsStore")
struct PlayStatsStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "PlayStatsStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("starts at zero")
    func startsAtZero() {
        let d = freshDefaults()
        let stats = PlayStatsStore.current(defaults: d)
        #expect(stats == PlayStats(wins: 0, losses: 0, draws: 0))
        #expect(stats.totalGames == 0)
    }

    @Test("record increments the right bucket and returns the updated tally")
    func recordIncrementsAndReturns() {
        let d = freshDefaults()
        var stats = PlayStatsStore.record(.win, defaults: d)
        #expect(stats == PlayStats(wins: 1, losses: 0, draws: 0))
        stats = PlayStatsStore.record(.win, defaults: d)
        #expect(stats.wins == 2)
        stats = PlayStatsStore.record(.loss, defaults: d)
        #expect(stats == PlayStats(wins: 2, losses: 1, draws: 0))
        stats = PlayStatsStore.record(.draw, defaults: d)
        #expect(stats == PlayStats(wins: 2, losses: 1, draws: 1))
        #expect(stats.totalGames == 4)
        // Persisted, not just returned.
        #expect(PlayStatsStore.current(defaults: d) == stats)
    }

    @Test("resetAll clears every bucket")
    func resetAllClears() {
        let d = freshDefaults()
        _ = PlayStatsStore.record(.win, defaults: d)
        _ = PlayStatsStore.record(.loss, defaults: d)

        PlayStatsStore.resetAll(defaults: d)

        #expect(PlayStatsStore.current(defaults: d) == PlayStats())
    }
}
