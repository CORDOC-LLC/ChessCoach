//  PuzzleStreakStore.swift
//  Tracks consecutive days with at least one puzzle solved. Fully local,
//  fully free -- no backend, no account required.
//
//  Day-boundary logic always goes through an injected `Calendar` (defaulting
//  to `.current`) rather than raw `Date` subtraction, so timezone-crossing
//  midnight doesn't corrupt the streak, and so tests can pin down exact
//  day-boundary behavior with a fixed calendar/date sequence instead of
//  depending on wall-clock time.
//
//  Write-through to iCloud (plan U7): every update also mirrors into the
//  injected `iCloudProgressSync` so the streak carries across the user's
//  own devices via their own iCloud. Streak state is scalar, not a set, so
//  remote merges are last-write-wins (see
//  `iCloudProgressSync.MergeStrategy.lastWriteWins`), unlike the solved-ID
//  sets in `PuzzleProgressStore`.

import Foundation

public enum PuzzleStreakStore {
    private static let lastSolvedDateKey = "puzzles.streak.lastSolvedDate"
    private static let currentStreakKey = "puzzles.streak.current"
    // Internal (not private) so `iCloudProgressSync` can register the
    // matching remote-merge rule against this shared prefix -- single
    // source of truth for the key shape.
    static let streakKeyPrefix = "puzzles.streak."

    /// The most recent day (start-of-day, per the injected calendar) a
    /// puzzle was solved, or `nil` if none has ever been solved.
    public static func lastSolvedDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSolvedDateKey) as? Date
    }

    /// Current consecutive-day streak. Zero if no puzzle has ever been
    /// solved.
    public static func currentStreak(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: currentStreakKey) as? Int ?? 0
    }

    /// Records a puzzle solve at `now` (device calendar day, per `calendar`):
    /// - same day as `lastSolvedDate` -> no-op (already counted today).
    /// - exactly one day after `lastSolvedDate` -> streak increments.
    /// - more than one day after (or no prior solve) -> streak resets to 1.
    /// Returns the resulting streak.
    @discardableResult
    public static func recordSolve(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard,
        sync: iCloudProgressSync = .shared
    ) -> Int {
        let today = calendar.startOfDay(for: now)

        guard let last = lastSolvedDate(defaults: defaults) else {
            defaults.set(today, forKey: lastSolvedDateKey)
            defaults.set(1, forKey: currentStreakKey)
            sync.write(key: lastSolvedDateKey, value: today)
            sync.write(key: currentStreakKey, value: 1)
            return 1
        }

        let lastDay = calendar.startOfDay(for: last)
        let dayDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        let newStreak: Int
        switch dayDiff {
        case 0:
            return currentStreak(defaults: defaults)
        case 1:
            newStreak = currentStreak(defaults: defaults) + 1
        default:
            newStreak = 1
        }

        defaults.set(today, forKey: lastSolvedDateKey)
        defaults.set(newStreak, forKey: currentStreakKey)
        sync.write(key: lastSolvedDateKey, value: today)
        sync.write(key: currentStreakKey, value: newStreak)
        return newStreak
    }

    /// Clears streak progress (for Settings' "Reset puzzle progress" family
    /// of actions).
    public static func reset(defaults: UserDefaults = .standard, sync: iCloudProgressSync = .shared) {
        defaults.removeObject(forKey: lastSolvedDateKey)
        defaults.removeObject(forKey: currentStreakKey)
        sync.write(key: lastSolvedDateKey, value: nil)
        sync.write(key: currentStreakKey, value: nil)
    }
}
