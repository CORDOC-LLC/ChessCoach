//  PuzzleProgressStore.swift
//  Which puzzles (by id) have been solved in each theme, so re-opening a
//  theme surfaces fresh puzzles first instead of replaying solved ones.

import Foundation

public enum PuzzleProgressStore {
    private static let keyPrefix = "puzzles.solved."
    private static func key(theme: String) -> String { "\(keyPrefix)\(theme)" }

    public static func solvedIDs(theme: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(theme: theme)) ?? [])
    }

    public static func markSolved(_ id: String, theme: String, defaults: UserDefaults = .standard) {
        var ids = solvedIDs(theme: theme, defaults: defaults)
        guard ids.insert(id).inserted else { return }
        defaults.set(Array(ids), forKey: key(theme: theme))
    }

    /// Clears solved-puzzle progress for every theme (Settings' "Reset puzzle
    /// progress" action) -- doesn't touch downloaded pack files, just which
    /// puzzles are marked done.
    public static func resetAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
