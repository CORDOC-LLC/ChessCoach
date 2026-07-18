//  PuzzleProgressStore.swift
//  Which puzzles (by id) have been solved in each theme, so re-opening a
//  theme surfaces fresh puzzles first instead of replaying solved ones.
//
//  Write-through to iCloud (plan U7): every update also mirrors into the
//  injected `iCloudProgressSync` so solved-puzzle progress carries across
//  the user's own devices via their own iCloud, merged as a *union* on the
//  way back in (never dropping an already-solved ID -- see
//  `iCloudProgressSync.MergeStrategy.unionStringSet`).

import Foundation

public enum PuzzleProgressStore {
    // Internal (not private) so `iCloudProgressSync` can register the
    // matching remote-merge rule against the same prefix -- single source
    // of truth for the key shape.
    static let keyPrefix = "puzzles.solved."
    private static func key(theme: String) -> String { "\(keyPrefix)\(theme)" }

    public static func solvedIDs(theme: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(theme: theme)) ?? [])
    }

    public static func markSolved(
        _ id: String,
        theme: String,
        defaults: UserDefaults = .standard,
        sync: iCloudProgressSync = .shared
    ) {
        var ids = solvedIDs(theme: theme, defaults: defaults)
        guard ids.insert(id).inserted else { return }
        defaults.set(Array(ids), forKey: key(theme: theme))
        sync.write(key: key(theme: theme), value: Array(ids))
    }

    /// Clears solved-puzzle progress for every theme (Settings' "Reset puzzle
    /// progress" action) -- doesn't touch downloaded pack files, just which
    /// puzzles are marked done.
    public static func resetAll(defaults: UserDefaults = .standard, sync: iCloudProgressSync = .shared) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
            sync.write(key: key, value: nil)
        }
    }
}
