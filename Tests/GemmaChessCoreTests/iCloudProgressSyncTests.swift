//  iCloudProgressSyncTests.swift
//  Exercises the write-through mirror and remote-change merge logic with an
//  in-memory `UbiquitousKeyValueStoring` double -- no dependency on a real
//  iCloud account in CI.

import Testing
import Foundation
@testable import GemmaChessCore

/// In-memory `UbiquitousKeyValueStoring` double. `nil` for a key it's never
/// seen stands in for "iCloud unavailable" / "nothing written yet".
final class MockUbiquitousKeyValueStore: UbiquitousKeyValueStoring, @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private(set) var synchronizeCallCount = 0

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    @discardableResult
    func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }
}

@Suite("iCloudProgressSync")
struct iCloudProgressSyncTests {

    private func freshDefaults() -> UserDefaults {
        let name = "iCloudProgressSyncTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Posts a simulated `didChangeExternallyNotification` through `center`
    /// carrying `changedKeys`, the same shape `NSUbiquitousKeyValueStore`
    /// itself would post.
    private func postExternalChange(_ changedKeys: [String], center: NotificationCenter) {
        center.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: changedKeys]
        )
    }

    // MARK: - Scenario 1: local update writes through to the KV store.

    @Test("marking a puzzle solved mirrors the solved-ID array into the KV store")
    func progressWritesThrough() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults)

        PuzzleProgressStore.markSolved("puzzle-1", theme: "fork", defaults: defaults, sync: sync)

        let mirrored = mock.object(forKey: "puzzles.solved.fork") as? [String]
        #expect(mirrored != nil)
        #expect(Set(mirrored ?? []) == ["puzzle-1"])
    }

    @Test("a rating update mirrors the new rating into the KV store")
    func ratingWritesThrough() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults)

        let newRating = PuzzleRatingStore.update(puzzleRating: 1200, correct: true, defaults: defaults, sync: sync)

        #expect(mock.object(forKey: PuzzleRatingStore.key) as? Int == newRating)
    }

    @Test("recording a solve mirrors both streak keys into the KV store")
    func streakWritesThrough() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!

        let streak = PuzzleStreakStore.recordSolve(now: now, calendar: cal, defaults: defaults, sync: sync)

        #expect(mock.object(forKey: "puzzles.streak.current") as? Int == streak)
        #expect(mock.object(forKey: "puzzles.streak.lastSolvedDate") != nil)
    }

    // MARK: - Scenario 2: remote solved-ID set merges as a union.

    @Test("remote solved-ID set merges as a union, never dropping a local solved ID")
    func solvedIDsMergeAsUnion() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let center = NotificationCenter()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults, notificationCenter: center)
        sync.registerMergeRule(keyPrefix: PuzzleProgressStore.keyPrefix, strategy: .unionStringSet)

        let key = "puzzles.solved.fork"
        // Local already has "a" and "b" solved.
        defaults.set(["a", "b"], forKey: key)
        // Remote (another device) has "b" and "c" -- "b" overlaps, "c" is new,
        // and critically the remote set does NOT include "a".
        mock.set(["b", "c"], forKey: key)

        postExternalChange([key], center: center)

        // Union of both sides -- "a" must not be lost even though the
        // remote snapshot didn't carry it.
        #expect(PuzzleProgressStore.solvedIDs(theme: "fork", defaults: defaults) == ["a", "b", "c"])
    }

    // MARK: - Scenario 3: remote scalar overwrites local (last-write-wins).

    @Test("remote rating value overwrites the local rating (last-write-wins)")
    func ratingLastWriteWins() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let center = NotificationCenter()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults, notificationCenter: center)
        sync.registerMergeRule(keyPrefix: PuzzleRatingStore.key, strategy: .lastWriteWins)

        defaults.set(1300, forKey: PuzzleRatingStore.key)
        mock.set(1450, forKey: PuzzleRatingStore.key)

        postExternalChange([PuzzleRatingStore.key], center: center)

        #expect(PuzzleRatingStore.currentRating(defaults: defaults) == 1450)
    }

    @Test("remote streak value overwrites the local streak (last-write-wins)")
    func streakLastWriteWins() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore()
        let center = NotificationCenter()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults, notificationCenter: center)
        sync.registerMergeRule(keyPrefix: "puzzles.streak.", strategy: .lastWriteWins)

        defaults.set(3, forKey: "puzzles.streak.current")
        mock.set(7, forKey: "puzzles.streak.current")

        postExternalChange(["puzzles.streak.current"], center: center)

        #expect(PuzzleStreakStore.currentStreak(defaults: defaults) == 7)
    }

    // MARK: - Scenario 4: iCloud unavailable -- local-only operation is unaffected.

    @Test("iCloud unavailable: writes don't crash, and local values survive an empty remote change")
    func iCloudUnavailableIsANoOp() {
        let defaults = freshDefaults()
        let mock = MockUbiquitousKeyValueStore() // never has anything set -- "not signed into iCloud"
        let center = NotificationCenter()
        let sync = iCloudProgressSync(keyValueStore: mock, defaults: defaults, notificationCenter: center)
        sync.registerPuzzleProgressMergeRules()

        // Local-only writes proceed normally.
        PuzzleProgressStore.markSolved("puzzle-1", theme: "pin", defaults: defaults, sync: sync)
        let rating = PuzzleRatingStore.update(puzzleRating: 1200, correct: true, defaults: defaults, sync: sync)
        defaults.set(5, forKey: "puzzles.streak.current")

        // Simulate a remote-change notification arriving for keys that the
        // (unavailable) KV store has no data for -- should be a no-op, not
        // a crash or a local value getting clobbered with nil/garbage.
        postExternalChange(
            ["puzzles.solved.pin", PuzzleRatingStore.key, "puzzles.streak.current"],
            center: center
        )

        #expect(PuzzleProgressStore.solvedIDs(theme: "pin", defaults: defaults) == ["puzzle-1"])
        #expect(PuzzleRatingStore.currentRating(defaults: defaults) == rating)
        #expect(PuzzleStreakStore.currentStreak(defaults: defaults) == 5)
    }
}
