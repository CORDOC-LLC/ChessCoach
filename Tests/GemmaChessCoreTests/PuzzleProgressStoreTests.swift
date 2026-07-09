//  PuzzleProgressStoreTests.swift
//  Which puzzles have been solved, per theme, persisted across instances.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("PuzzleProgressStore")
struct PuzzleProgressStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "PuzzleProgressStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("no solved puzzles by default")
    func emptyByDefault() {
        let d = freshDefaults()
        #expect(PuzzleProgressStore.solvedIDs(theme: "fork", defaults: d).isEmpty)
    }

    @Test("marking solved persists and is scoped per theme")
    func marksSolvedPerTheme() {
        let d = freshDefaults()
        PuzzleProgressStore.markSolved("abc12", theme: "fork", defaults: d)
        PuzzleProgressStore.markSolved("xyz99", theme: "fork", defaults: d)
        PuzzleProgressStore.markSolved("abc12", theme: "pin", defaults: d)

        #expect(PuzzleProgressStore.solvedIDs(theme: "fork", defaults: d) == ["abc12", "xyz99"])
        #expect(PuzzleProgressStore.solvedIDs(theme: "pin", defaults: d) == ["abc12"])
    }

    @Test("resetAll clears every theme's progress (Settings' reset action)")
    func resetAllClearsEveryTheme() {
        let d = freshDefaults()
        PuzzleProgressStore.markSolved("abc12", theme: "fork", defaults: d)
        PuzzleProgressStore.markSolved("abc12", theme: "pin", defaults: d)

        PuzzleProgressStore.resetAll(defaults: d)

        #expect(PuzzleProgressStore.solvedIDs(theme: "fork", defaults: d).isEmpty)
        #expect(PuzzleProgressStore.solvedIDs(theme: "pin", defaults: d).isEmpty)
    }
}
