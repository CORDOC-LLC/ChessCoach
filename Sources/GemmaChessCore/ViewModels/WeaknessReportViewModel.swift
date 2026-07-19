//  WeaknessReportViewModel.swift
//  Drives the Weakness Report screen (plan U7): loads the current
//  CoachingProfile from HistoryStore, exposes the free teaser stat and the
//  Pro-gated cached/fresh narrative, and gates "Refresh" via
//  WeaknessReportStore's game-count threshold.

import Foundation

@MainActor
@Observable
public final class WeaknessReportViewModel {

    public private(set) var teaserMotif: String?
    public private(set) var narrative: String?
    public private(set) var isLoading = false
    public private(set) var loadError: String?
    public var showPaywall = false
    public private(set) var canRefresh = false
    /// The named flaw's free-content deep-link target (a Lesson/puzzle theme
    /// id), if the report named a motif with a mapping (R1/R9).
    public private(set) var suggestedThemeID: String?

    private let historyBaseDir: URL?
    private let progressDefaults: UserDefaults
    private let client: WeaknessReportClient

    public init(
        historyBaseDir: URL? = nil,
        progressDefaults: UserDefaults = .standard,
        client: WeaknessReportClient = WeaknessReportClient()
    ) {
        self.historyBaseDir = historyBaseDir
        self.progressDefaults = progressDefaults
        self.client = client
    }

    private var profile: CoachingProfile {
        let store = HistoryStore(baseDir: historyBaseDir)
        return CoachingProfileBuilder.buildProfile(playerID: "me", store: store)
    }

    /// Cheap, free, local-only -- safe to call from `onAppear` on Home for
    /// every user regardless of Pro status (R6).
    public func loadTeaser() {
        teaserMotif = CoachingProfileBuilder.topTeaserMotif(profile)
    }

    /// Loads the cached narrative (if any) and recomputes the refresh gate.
    /// Never touches the network -- call `generate()` explicitly for that.
    public func loadCached() {
        let current = profile
        narrative = WeaknessReportStore.cachedNarrative(defaults: progressDefaults)
        canRefresh = WeaknessReportStore.canRefresh(
            currentGameCount: current.gamesAnalyzed, defaults: progressDefaults)
        if let top = current.recent?.topMotifs.first {
            suggestedThemeID = MotifFreeContentMapping.themeID(forMotif: top.motif)
        }
    }

    /// Generates a fresh narrative (first-ever generation, or an explicit
    /// refresh once `canRefresh` allows it). Pro-gated inside
    /// `WeaknessReportClient.generateReport` -- a `ProRequiredError` here
    /// surfaces the paywall instead of a generic error, mirroring every other
    /// coach call site.
    public func generate() async {
        let current = profile
        guard let facts = CoachingProfileBuilder.weaknessReportFacts(current) else {
            loadError = "Play a few more games first -- there's not enough data yet for a report."
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let text = try await client.generateReport(facts: facts)
            narrative = text
            WeaknessReportStore.recordGenerated(
                narrative: text, gameCount: current.gamesAnalyzed, defaults: progressDefaults)
            canRefresh = false
        } catch is ProRequiredError {
            showPaywall = true
        } catch let error as CoachError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }
}
