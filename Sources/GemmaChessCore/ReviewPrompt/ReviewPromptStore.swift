//  ReviewPromptStore.swift
//  Local trigger/cooldown/cap tracking for the App Store review soft-ask
//  (plan R8/KTD-6/KTD-7). Entirely local -- no backend, no account. This
//  store owns none of the counting itself: callers pass in the existing
//  `LessonProgressStore`/`PlayStatsStore` totals (lessons completed, games
//  played) rather than this store duplicating those counters, per the
//  plan's Open Questions ("reads existing totals directly" is preferred
//  over a parallel counter -- one fewer place these numbers can drift out
//  of sync).
//
//  This does NOT decide whether to show Apple's system review sheet --
//  that's `@Environment(\.requestReview)`, called by the UI only after the
//  user taps through this store's soft-ask (KTD-6). This store only answers
//  "is now an appropriate moment to show the soft-ask at all."
//
//  Tuning (easy to retune later, single local store, no external
//  dependents -- see the plan's Open Questions):
//   - `lessonsCompletedThreshold` = 3 -- a handful of finished lessons is
//     enough of a "genuinely used the app" signal without waiting so long
//     that an engaged user never sees the ask.
//   - `gamesPlayedThreshold` = 3 -- same rationale, mirrored for players
//     who mostly use Play rather than Lessons; either crossing qualifies.
//   - `showCountCap` = 3 -- a small, permanent lifetime cap. Once reached,
//     `shouldPrompt` is false forever, regardless of cooldown -- an
//     engaged user who has already said "not now" (or "rate") three times
//     should never be nagged again, even though Apple's own
//     `SKStoreReviewController` might still be willing to show its sheet.
//   - `cooldownInterval` = 90 days -- long enough that the soft-ask never
//     feels like nagging between asks, short enough that a long-lived user
//     could plausibly see it a second or third time across the cap.
//
//  Injectable `Date`, mirroring `PuzzleStreakStore`'s testability pattern --
//  no reliance on wall-clock time in tests.

import Foundation

public enum ReviewPromptStore {
    public static let lessonsCompletedThreshold = 3
    public static let gamesPlayedThreshold = 3
    public static let showCountCap = 3
    public static let cooldownInterval: TimeInterval = 90 * 24 * 60 * 60

    private static let timesShownKey = "reviewPrompt.timesShown"
    private static let lastShownDateKey = "reviewPrompt.lastShownDate"

    /// How many times the soft-ask has ever been shown.
    public static func timesShown(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: timesShownKey) as? Int ?? 0
    }

    /// The date the soft-ask was last shown, or `nil` if never shown.
    public static func lastShownDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastShownDateKey) as? Date
    }

    /// Whether the review soft-ask should be shown right now, given the
    /// caller's current engagement totals (from `LessonProgressStore`'s
    /// completed-lesson count and `PlayStats.totalGames`, per the plan --
    /// this store does not read those directly so it stays independent of
    /// their storage shape).
    ///
    /// Gate order (mirrors the plan's state diagram):
    /// 1. Neither threshold crossed -> false.
    /// 2. Show-count cap already reached -> false, permanently.
    /// 3. Still within the cooldown window since the last show -> false.
    /// 4. Otherwise (threshold crossed, cap available, cooldown elapsed or
    ///    never shown) -> true.
    public static func shouldPrompt(
        lessonsCompleted: Int,
        gamesPlayed: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        let thresholdCrossed = lessonsCompleted >= lessonsCompletedThreshold
            || gamesPlayed >= gamesPlayedThreshold
        guard thresholdCrossed else { return false }

        guard timesShown(defaults: defaults) < showCountCap else { return false }

        if let last = lastShownDate(defaults: defaults) {
            let elapsed = now.timeIntervalSince(last)
            guard elapsed >= cooldownInterval else { return false }
        }

        return true
    }

    /// Records that the soft-ask was just shown at `now` -- increments the
    /// lifetime show count and starts a fresh cooldown window. Called
    /// regardless of whether the user then taps "Rate" or "Not now" (both
    /// count as a "shown," per KTD-6 -- only the OS's own
    /// `requestReview()` call differs between the two, not this store's
    /// bookkeeping).
    public static func recordShown(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(timesShown(defaults: defaults) + 1, forKey: timesShownKey)
        defaults.set(now, forKey: lastShownDateKey)
    }

    /// Clears all review-prompt state (for Settings' reset-progress family
    /// of actions, mirroring `PuzzleStreakStore.reset()`).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: timesShownKey)
        defaults.removeObject(forKey: lastShownDateKey)
    }
}
