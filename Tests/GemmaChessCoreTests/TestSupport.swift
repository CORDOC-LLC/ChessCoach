//  TestSupport.swift
//  Shared test helpers.

import Foundation
@testable import GemmaChessCore

@MainActor
extension PlayViewModel {
    /// A `PlayViewModel` wired to scratch, per-call persistence -- never the real
    /// Application Support directory or `UserDefaults.standard`. Every checkpoint
    /// now writes to disk (see `persistCheckpoint`), so plain `PlayViewModel()` in
    /// a test would race other parallel test suites over the same shared files.
    static func forTesting(coach: CoachOrchestrator = CoachOrchestrator()) -> PlayViewModel {
        let token = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayViewModelTests-\(token)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "PlayViewModelTests-\(token)")!
        return PlayViewModel(coach: coach, savedGamesBaseDir: dir, savedGamesDefaults: defaults)
    }
}

@MainActor
extension PuzzleViewModel {
    /// A `PuzzleViewModel` wired to scratch, per-call storage -- never the
    /// real Application Support directory or `UserDefaults.standard`.
    static func forTesting() -> PuzzleViewModel {
        let token = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PuzzleViewModelTests-\(token)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "PuzzleViewModelTests-\(token)")!
        return PuzzleViewModel(progressDefaults: defaults, puzzleBaseDir: dir)
    }
}
