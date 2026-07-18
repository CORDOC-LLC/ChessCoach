//  PuzzleRatingStore.swift
//  A local, entirely free "Elo-lite" puzzle-solving rating. This is NOT a
//  claim about overall playing strength -- it only tracks how well the
//  solver is doing against the difficulty (Puzzle.rating) of the puzzles
//  they've attempted, the same way lichess's puzzle rating works. No
//  network call, no backend, just a persisted Int updated after every
//  attempt.
//
//  Tuning (easy to retune later, single local scalar, no external
//  dependents):
//   - `defaultRating` = 1200 -- a conventional "average club player" seed
//     so early puzzles (which skew easy-to-medium) don't feel like a big
//     upset either way.
//   - `kFactor` = 24 -- a middling K, borrowed from standard chess Elo
//     "regular player" conventions: responsive enough that a session of
//     puzzles visibly moves the number, but not so twitchy that a single
//     lucky/unlucky puzzle swings it wildly.
//   - `floor` = 400 -- a losing streak (especially early, before the
//     rating has climbed off its seed) can't drag the number into
//     nonsensical territory.
//
//  Write-through to iCloud (plan U7): every update also mirrors into the
//  injected `iCloudProgressSync` so the rating carries across the user's
//  own devices via their own iCloud. Ratings are a scalar, not a set, so
//  remote merges are last-write-wins (see
//  `iCloudProgressSync.MergeStrategy.lastWriteWins`), unlike the solved-ID
//  sets in `PuzzleProgressStore`.

import Foundation

public enum PuzzleRatingStore {
    public static let defaultRating = 1200
    public static let kFactor = 24.0
    public static let floor = 400

    // Internal (not private) so `iCloudProgressSync` can register the
    // matching remote-merge rule against the same key -- single source of
    // truth for the key shape.
    static let key = "puzzles.rating"

    /// The solver's current puzzle rating, or `defaultRating` on a fresh
    /// install (nothing persisted yet).
    public static func currentRating(defaults: UserDefaults = .standard) -> Int {
        (defaults.object(forKey: key) as? Int) ?? defaultRating
    }

    /// Updates the persisted rating after one puzzle attempt and returns the
    /// new value. Standard Elo expected-score formula:
    /// `expected = 1 / (1 + 10^((puzzleRating - userRating) / 400))`,
    /// moving the rating toward 1 (correct) or 0 (incorrect) scaled by
    /// `kFactor`, then clamped to `floor`.
    @discardableResult
    public static func update(
        puzzleRating: Int,
        correct: Bool,
        defaults: UserDefaults = .standard,
        sync: iCloudProgressSync = .shared
    ) -> Int {
        let userRating = currentRating(defaults: defaults)
        let expected = 1.0 / (1.0 + pow(10.0, Double(puzzleRating - userRating) / 400.0))
        let actual = correct ? 1.0 : 0.0
        let delta = kFactor * (actual - expected)
        let newRating = max(floor, Int((Double(userRating) + delta).rounded()))
        defaults.set(newRating, forKey: key)
        sync.write(key: key, value: newRating)
        return newRating
    }
}
