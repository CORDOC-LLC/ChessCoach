//  WeaknessReportStore.swift
//  Local cache for the Weakness Report's narrative (plan U5/R5): the
//  narrative is generated once and cached, not regenerated on every open --
//  "Refresh" stays disabled until enough new unified-history games have
//  accumulated since the last generation (KTD-5: 5 games), avoiding paying
//  for an identical LLM call with no new data most of the time.
//
//  UserDefaults-backed, injectable, enum-namespace style, mirroring
//  ReviewPromptStore.

import Foundation

public enum WeaknessReportStore {
    /// How many new unified-history games must accumulate since the last
    /// generation before "Refresh" is enabled again (KTD-5).
    public static let refreshGameThreshold = 5

    private static let narrativeKey = "weaknessReport.narrative"
    private static let generatedAtKey = "weaknessReport.generatedAt"
    private static let gameCountAtGenerationKey = "weaknessReport.gameCountAtGeneration"

    /// The cached narrative, or `nil` if never generated.
    public static func cachedNarrative(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: narrativeKey)
    }

    /// When the cached narrative was generated, or `nil` if never generated.
    public static func generatedAt(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: generatedAtKey) as? Date
    }

    /// Whether generating a fresh report is currently allowed: always true
    /// with no cached report yet, otherwise only once `currentGameCount` has
    /// grown by at least `refreshGameThreshold` since the last generation.
    public static func canRefresh(currentGameCount: Int, defaults: UserDefaults = .standard) -> Bool {
        guard cachedNarrative(defaults: defaults) != nil else { return true }
        let atGeneration = defaults.object(forKey: gameCountAtGenerationKey) as? Int ?? 0
        return currentGameCount - atGeneration >= refreshGameThreshold
    }

    /// Caches a freshly generated narrative alongside the unified-history
    /// game count at the moment it was generated, so a later `canRefresh`
    /// call knows how many new games have accumulated since.
    public static func recordGenerated(
        narrative: String, gameCount: Int, now: Date = Date(), defaults: UserDefaults = .standard
    ) {
        defaults.set(narrative, forKey: narrativeKey)
        defaults.set(now, forKey: generatedAtKey)
        defaults.set(gameCount, forKey: gameCountAtGenerationKey)
    }

    /// Clears all cached report state (Settings' reset-progress family).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: narrativeKey)
        defaults.removeObject(forKey: generatedAtKey)
        defaults.removeObject(forKey: gameCountAtGenerationKey)
    }
}
