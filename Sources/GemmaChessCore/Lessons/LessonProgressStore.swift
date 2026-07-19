//  LessonProgressStore.swift
//  Per-lesson completion tracking, keyed by Lesson.id. Entirely local -- no
//  backend, no coach call.
//
//  Write-through to iCloud: every update also mirrors into the injected
//  `iCloudProgressSync` so lesson progress carries across the user's own
//  devices via their own iCloud. Unlike the per-theme solved-ID sets in
//  `PuzzleProgressStore` (which merge as a union), lesson progress is stored
//  as a single JSON blob (mirrors `OpeningTrainerStore`'s style) and merges
//  last-write-wins -- there's no meaningful per-lesson union to compute
//  across an opaque blob, and losing a little progress on a rare concurrent-
//  device conflict is an acceptable trade-off for the simplicity, consistent
//  with how `PuzzleRatingStore`/`PuzzleStreakStore` already merge their
//  scalars.

import Foundation

/// This lesson's completion state.
public enum LessonProgress: Codable, Equatable, Sendable {
    case notStarted
    case inProgress(solvedCount: Int)
    case completed
}

/// Per-lesson progress, persisted flat in `UserDefaults` as a single JSON
/// blob keyed by `Lesson.id` (mirrors `OpeningTrainerStore`'s style).
public enum LessonProgressStore {
    // Internal (not private) so `iCloudProgressSync` can register the
    // matching remote-merge rule against the same key -- single source of
    // truth for the key shape.
    static let defaultsKey = "lessons.progress"

    // MARK: Reading

    public static func allProgress(defaults: UserDefaults = .standard) -> [String: LessonProgress] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: LessonProgress].self, from: data)
        else { return [:] }
        return decoded
    }

    /// A lesson's current progress, or `.notStarted` if never attempted.
    public static func progress(for lessonID: String, defaults: UserDefaults = .standard) -> LessonProgress {
        allProgress(defaults: defaults)[lessonID] ?? .notStarted
    }

    // MARK: Recording attempts

    /// Records this lesson's progress after a practice attempt.
    /// `isComplete` takes precedence over `solvedCount` -- once every
    /// puzzle in the lesson is solved, the lesson is `.completed`, a
    /// terminal state (re-practicing a completed lesson doesn't demote it).
    @discardableResult
    public static func recordAttempt(
        lessonID: String,
        solvedCount: Int,
        isComplete: Bool,
        defaults: UserDefaults = .standard,
        sync: iCloudProgressSync = .shared
    ) -> LessonProgress {
        var all = allProgress(defaults: defaults)
        let entry: LessonProgress = isComplete ? .completed : .inProgress(solvedCount: solvedCount)
        all[lessonID] = entry
        save(all, defaults: defaults, sync: sync)
        return entry
    }

    /// Clears every lesson's progress (a Settings-style reset action).
    public static func resetAll(defaults: UserDefaults = .standard, sync: iCloudProgressSync = .shared) {
        defaults.removeObject(forKey: defaultsKey)
        sync.write(key: defaultsKey, value: nil)
    }

    // MARK: Private

    private static func save(_ all: [String: LessonProgress], defaults: UserDefaults, sync: iCloudProgressSync) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: defaultsKey)
        sync.write(key: defaultsKey, value: data)
    }
}
