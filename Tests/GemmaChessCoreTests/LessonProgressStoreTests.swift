//  LessonProgressStoreTests.swift
//  Covers LessonProgressStore's three-state progress tracking, persistence
//  round-trip, iCloud write-through, and the lesson catalog's integrity
//  against real puzzle theme ids.

import Testing
import Foundation
@testable import GemmaChessCore

private final class MockKeyValueStore: UbiquitousKeyValueStoring {
    private var storage: [String: Any] = [:]
    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
    func synchronize() -> Bool { true }
}

@Suite("LessonProgressStore")
struct LessonProgressStoreTests {

    @Test("a fresh install reports every lesson as not started")
    func freshInstallIsNotStarted() {
        let defaults = UserDefaults(suiteName: #function)!
        #expect(LessonProgressStore.progress(for: "fork", defaults: defaults) == .notStarted)
    }

    @Test("recording a partial attempt sets inProgress with the solved count")
    func partialAttemptSetsInProgress() {
        let defaults = UserDefaults(suiteName: #function)!
        let result = LessonProgressStore.recordAttempt(
            lessonID: "fork", solvedCount: 5, isComplete: false, defaults: defaults
        )
        #expect(result == .inProgress(solvedCount: 5))
        #expect(LessonProgressStore.progress(for: "fork", defaults: defaults) == .inProgress(solvedCount: 5))
    }

    @Test("recording completion sets completed regardless of solved count")
    func completionSetsCompleted() {
        let defaults = UserDefaults(suiteName: #function)!
        let result = LessonProgressStore.recordAttempt(
            lessonID: "fork", solvedCount: 15, isComplete: true, defaults: defaults
        )
        #expect(result == .completed)
    }

    @Test("progress persists across a fresh read of the same UserDefaults suite")
    func persistsAcrossFreshRead() {
        let defaults = UserDefaults(suiteName: #function)!
        LessonProgressStore.recordAttempt(lessonID: "pin", solvedCount: 8, isComplete: false, defaults: defaults)

        // Simulate a fresh store instance by reading via the same suite name.
        #expect(LessonProgressStore.progress(for: "pin", defaults: defaults) == .inProgress(solvedCount: 8))
    }

    @Test("a write mirrors into the injected iCloud sync")
    func writeMirrorsToICloudSync() {
        let defaults = UserDefaults(suiteName: #function)!
        let kvStore = MockKeyValueStore()
        let sync = iCloudProgressSync(keyValueStore: kvStore, defaults: defaults)

        LessonProgressStore.recordAttempt(
            lessonID: "skewer", solvedCount: 3, isComplete: false, defaults: defaults, sync: sync
        )

        #expect(kvStore.object(forKey: LessonProgressStore.defaultsKey) != nil)
    }

    @Test("resetAll clears progress and mirrors the removal to iCloud sync")
    func resetAllClearsProgress() {
        let defaults = UserDefaults(suiteName: #function)!
        let kvStore = MockKeyValueStore()
        let sync = iCloudProgressSync(keyValueStore: kvStore, defaults: defaults)
        LessonProgressStore.recordAttempt(
            lessonID: "fork", solvedCount: 5, isComplete: false, defaults: defaults, sync: sync
        )

        LessonProgressStore.resetAll(defaults: defaults, sync: sync)

        #expect(LessonProgressStore.progress(for: "fork", defaults: defaults) == .notStarted)
        #expect(kvStore.object(forKey: LessonProgressStore.defaultsKey) == nil)
    }

    @Test("every lesson's theme matches a real, existing curated puzzle theme id")
    func catalogThemesAreReal() {
        // The curated theme set from PuzzleData/README.md / scripts/curate-puzzles.py.
        let knownThemes: Set<String> = [
            "fork", "pin", "skewer", "discoveredAttack", "doubleCheck", "backRankMate",
            "smotheredMate", "hangingPiece", "trappedPiece", "sacrifice", "deflection",
            "attraction", "clearance", "xRayAttack", "zugzwang", "mateIn1", "mateIn2",
            "mateIn3", "endgame", "opening",
        ]
        for lesson in LessonCatalog.allLessons {
            #expect(knownThemes.contains(lesson.theme), "Lesson \(lesson.id) references unknown theme \(lesson.theme)")
        }
    }

    @Test("every lesson has a non-empty, original body text and a positive puzzle count")
    func catalogLessonsAreWellFormed() {
        for lesson in LessonCatalog.allLessons {
            #expect(!lesson.bodyText.isEmpty)
            #expect(lesson.puzzleCount > 0)
        }
    }

    @Test("lesson ids are unique across the whole catalog")
    func lessonIDsAreUnique() {
        let ids = LessonCatalog.allLessons.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("LessonCatalog.lesson(id:) resolves a known id and returns nil for an unknown one")
    func lessonLookupByID() {
        #expect(LessonCatalog.lesson(id: "fork")?.theme == "fork")
        #expect(LessonCatalog.lesson(id: "not-a-real-lesson") == nil)
    }
}
