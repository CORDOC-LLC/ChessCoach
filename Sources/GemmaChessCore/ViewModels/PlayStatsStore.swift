//  PlayStatsStore.swift
//  Lifetime win/loss/draw tally across every Play mode game, persisted
//  on-device (UserDefaults -- three integers, no need for anything heavier).
//  Shown in the game-over banner and in Settings.

import Foundation

/// How a finished game went for the user. A top-level type (not nested in
/// PlayViewModel) so PlayStatsStore -- a plain persistence utility -- doesn't
/// have to depend on the view model to name it.
public enum PlayOutcome: Equatable, Sendable {
    case win, loss, draw
}

public struct PlayStats: Equatable, Sendable {
    public var wins: Int
    public var losses: Int
    public var draws: Int

    public init(wins: Int = 0, losses: Int = 0, draws: Int = 0) {
        self.wins = wins; self.losses = losses; self.draws = draws
    }

    public var totalGames: Int { wins + losses + draws }
}

public enum PlayStatsStore {
    private static let winsKey = "playStats.wins"
    private static let lossesKey = "playStats.losses"
    private static let drawsKey = "playStats.draws"

    public static func current(defaults: UserDefaults = .standard) -> PlayStats {
        PlayStats(
            wins: defaults.integer(forKey: winsKey),
            losses: defaults.integer(forKey: lossesKey),
            draws: defaults.integer(forKey: drawsKey)
        )
    }

    /// Records one finished game's outcome and returns the updated tally, so
    /// the caller doesn't need a separate `current()` read after.
    @discardableResult
    public static func record(_ outcome: PlayOutcome, defaults: UserDefaults = .standard) -> PlayStats {
        var stats = current(defaults: defaults)
        switch outcome {
        case .win: stats.wins += 1; defaults.set(stats.wins, forKey: winsKey)
        case .loss: stats.losses += 1; defaults.set(stats.losses, forKey: lossesKey)
        case .draw: stats.draws += 1; defaults.set(stats.draws, forKey: drawsKey)
        }
        return stats
    }

    /// Settings' "Reset statistics" action.
    public static func resetAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: winsKey)
        defaults.removeObject(forKey: lossesKey)
        defaults.removeObject(forKey: drawsKey)
    }
}
