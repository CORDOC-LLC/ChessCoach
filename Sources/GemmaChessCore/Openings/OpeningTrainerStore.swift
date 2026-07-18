//  OpeningTrainerStore.swift
//  Local spaced-repetition-style familiarity tracking for the Opening Trainer,
//  keyed by opening line (Openings.OpeningLine.id). Entirely local -- no
//  backend, no coach call; this only tracks how well the user knows a line
//  they've drilled against the vendored ECO book.

import Foundation

/// This line's practice state: how well-known it is and when it's next due.
public struct OpeningFamiliarity: Codable, Equatable, Sendable {
    /// 0...OpeningTrainerStore.maxLevel. Advances one step per correct move,
    /// capped at the top of the review schedule.
    public var level: Int
    /// Not due for practice again until this date (pushed further out each
    /// time `level` advances; pulled back to "now" on a miss).
    public var nextReviewDate: Date
    /// Set once the line has been played correctly start-to-finish at the top
    /// familiarity level -- a terminal state so a well-known line stops
    /// climbing forever and instead just gets resurfaced on the long schedule.
    public var isLearned: Bool

    public init(level: Int, nextReviewDate: Date, isLearned: Bool) {
        self.level = level
        self.nextReviewDate = nextReviewDate
        self.isLearned = isLearned
    }
}

/// Per-line familiarity, persisted flat in `UserDefaults` (mirrors
/// `PuzzleProgressStore`'s dependency-injectable style) as a single JSON blob
/// keyed by `OpeningLine.id`.
public enum OpeningTrainerStore {

    /// Spaced-repetition delay schedule, in days, indexed by familiarity level
    /// after a correct rep. Fixed steps rather than an SM-2 ease factor --
    /// simple and good enough for a free local drill mode. The line is
    /// considered "learned" once it tops out (see `recordAttempt`), rather
    /// than climbing forever.
    static let reviewIntervalsDays: [Int] = [1, 2, 4, 7, 14, 30, 60]

    /// The top of the review schedule -- `level` never exceeds this.
    public static var maxLevel: Int { reviewIntervalsDays.count - 1 }

    private static let defaultsKey = "openings.trainer.familiarity"

    // MARK: Reading

    public static func allFamiliarity(defaults: UserDefaults = .standard) -> [String: OpeningFamiliarity] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: OpeningFamiliarity].self, from: data)
        else { return [:] }
        return decoded
    }

    public static func familiarity(
        for lineID: String, defaults: UserDefaults = .standard
    ) -> OpeningFamiliarity? {
        allFamiliarity(defaults: defaults)[lineID]
    }

    /// Lines due for practice now: never-attempted lines (no stored entry),
    /// plus attempted-but-not-yet-learned lines whose `nextReviewDate` has
    /// passed. Fully learned lines are excluded once due again would just mean
    /// "resurface on the far-out schedule" -- callers that want spaced
    /// refreshers of learned lines can still query `allFamiliarity` directly.
    public static func linesDueForReview(
        from lines: [Openings.OpeningLine], now: Date = Date(), defaults: UserDefaults = .standard
    ) -> [Openings.OpeningLine] {
        let all = allFamiliarity(defaults: defaults)
        return lines.filter { line in
            guard let entry = all[line.id] else { return true }
            return !entry.isLearned && entry.nextReviewDate <= now
        }
    }

    // MARK: Recording attempts

    /// Records one move attempt against `lineID`'s familiarity.
    ///
    /// - `correct`: whether the attempted move matched the line's next move.
    /// - `isLineComplete`: true when this attempt was the line's last move --
    ///   a correct final move both advances the level and, once the level has
    ///   topped out the review schedule, marks the line fully learned (a
    ///   terminal state instead of climbing forever).
    ///
    /// An incorrect move drops the level (never below zero) and clears
    /// `isLearned`, and pulls the next review back to "now" -- the line needs
    /// re-practice, not a long wait.
    @discardableResult
    public static func recordAttempt(
        correct: Bool,
        lineID: String,
        isLineComplete: Bool,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> OpeningFamiliarity {
        var all = allFamiliarity(defaults: defaults)
        var entry = all[lineID] ?? OpeningFamiliarity(level: 0, nextReviewDate: now, isLearned: false)

        if correct {
            entry.level = min(entry.level + 1, maxLevel)
            let days = reviewIntervalsDays[entry.level]
            entry.nextReviewDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            if isLineComplete && entry.level >= maxLevel {
                entry.isLearned = true
            }
        } else {
            entry.level = max(entry.level - 2, 0)
            entry.nextReviewDate = now
            entry.isLearned = false
        }

        all[lineID] = entry
        save(all, defaults: defaults)
        return entry
    }

    /// Clears every line's practice progress (a Settings-style reset action).
    public static func resetAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: Private

    private static func save(_ all: [String: OpeningFamiliarity], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
