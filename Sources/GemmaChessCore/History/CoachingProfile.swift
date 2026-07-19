//  CoachingProfile.swift
//  U10 — derived coaching profile. Port of `build_profile`, `_aggregate`,
//  `_view_summary`, and `format_profile_for_prompt` from `server/core/history.py`.
//
//  Aggregates a player's `GameRecord`s into a small, prompt-ready profile: a "recent
//  form" sliding window plus an optional "lifetime" view. The split lets coaching adapt
//  as a player improves (recent weaknesses surface; old, fixed ones fade out of the
//  window). `formatProfileForPrompt` renders the compact `profileFacts` string the
//  `CoachPromptBuilder.chatPrompt` consumes (nil when there's nothing to say).

import Foundation

/// Aggregated stats for coaching, built from a player's history. Port of `build_profile`.
public struct CoachingProfile: Codable, Sendable, Equatable {

    public struct ResultTally: Codable, Sendable, Equatable {
        public var win: Int
        public var loss: Int
        public var draw: Int
        public init(win: Int = 0, loss: Int = 0, draw: Int = 0) {
            self.win = win; self.loss = loss; self.draw = draw
        }
    }

    public struct MistakeTotals: Codable, Sendable, Equatable {
        public var inaccuracy: Int
        public var mistake: Int
        public var blunder: Int
        public init(inaccuracy: Int = 0, mistake: Int = 0, blunder: Int = 0) {
            self.inaccuracy = inaccuracy; self.mistake = mistake; self.blunder = blunder
        }
    }

    public struct MistakeRates: Codable, Sendable, Equatable {
        public var inaccuracy: Double
        public var mistake: Double
        public var blunder: Double
        public init(inaccuracy: Double = 0, mistake: Double = 0, blunder: Double = 0) {
            self.inaccuracy = inaccuracy; self.mistake = mistake; self.blunder = blunder
        }
    }

    public struct PhaseLossTotal: Codable, Sendable, Equatable {
        public var opening: Double
        public var middlegame: Double
        public var endgame: Double
        public init(opening: Double = 0, middlegame: Double = 0, endgame: Double = 0) {
            self.opening = opening; self.middlegame = middlegame; self.endgame = endgame
        }
    }

    public struct MotifCount: Codable, Sendable, Equatable {
        public var motif: String
        public var count: Int
    }

    public struct SpeedStat: Codable, Sendable, Equatable {
        public var speed: String
        public var games: Int
        public var avgAccuracy: Double?
        public var blundersPerGame: Double?
    }

    public struct OpeningStat: Codable, Sendable, Equatable {
        public var opening: String
        public var games: Int
        public var avgAccuracy: Double?
    }

    /// One aggregate view (recent window or lifetime). Mirrors the dict from `_aggregate`.
    public struct View: Codable, Sendable, Equatable {
        public var window: Int?            // recent view only; nil = all
        public var games: Int
        public var avgAccuracy: Double?
        public var results: ResultTally
        public var mistakeTotals: MistakeTotals
        public var mistakesPerGame: MistakeRates
        public var topMotifs: [MotifCount]
        public var phaseLossTotal: PhaseLossTotal
        public var weakestPhase: String?
        public var bySpeed: [SpeedStat]
        public var openings: [OpeningStat]
    }

    public struct RecentGame: Codable, Sendable, Equatable {
        public var date: String?
        public var opening: String?
        public var accuracy: Double?
        public var result: String?
        public var blunders: Int
    }

    public var playerID: String
    public var displayName: String
    public var gamesAnalyzed: Int
    public var generatedAt: String
    public var recent: View?
    public var lifetime: View?
    public var recentGames: [RecentGame]
}

/// Structured facts sent to `chesscoach-gateway`'s `/api/weaknessReport`
/// (plan U3/U4) -- deliberately just numbers, never prompt text. Field names
/// mirror the gateway's Zod schema exactly; keep the two in sync by hand
/// (there is no shared type between the Swift client and the TypeScript
/// gateway repo).
public struct WeaknessReportFacts: Codable, Sendable, Equatable {
    public struct MotifCount: Codable, Sendable, Equatable {
        public var motif: String
        public var count: Int
    }
    public var topMotifs: [MotifCount]
    public var weakestPhase: String?
    public var recentAccuracy: Double?
    public var lifetimeAccuracy: Double?
    public var gamesAnalyzed: Int
}

public enum CoachingProfileBuilder {

    /// Sliding-window size for "recent form" (last N games; <= 0 = all). Source default.
    public static let recentWindow = 100
    /// Lifetime view size (nil = all history; 0 = omit; positive N = last N). Source default.
    public static let lifetimeWindow: Int? = nil

    /// Build a hybrid coaching profile for a player from their (already loaded) records.
    /// Port of `build_profile`. `recentWindow`/`lifetime` mirror the source's config
    /// (`PROFILE_RECENT_WINDOW` / `PROFILE_LIFETIME`) and default to those values.
    public static func buildProfile(
        playerID: String, records allRecords: [GameRecord], displayName: String? = nil,
        recentWindow: Int = CoachingProfileBuilder.recentWindow,
        lifetime: Int? = CoachingProfileBuilder.lifetimeWindow
    ) -> CoachingProfile {
        let records = allRecords
            .filter { $0.playerID == playerID }
            .sorted { $0.analyzedAt < $1.analyzedAt }

        var profile = CoachingProfile(
            playerID: playerID,
            displayName: displayName ?? playerID,
            gamesAnalyzed: records.count,
            generatedAt: HistoryStore.nowISO(),
            recent: nil, lifetime: nil, recentGames: [])
        if records.isEmpty { return profile }

        let recentRecords = recentWindow <= 0 ? records : Array(records.suffix(recentWindow))
        var recentView = aggregate(recentRecords)
        recentView.window = recentWindow > 0 ? recentWindow : nil
        profile.recent = recentView

        if lifetime != 0 {
            let lifetimeRecords = lifetime == nil
                ? records : Array(records.suffix(lifetime!))
            profile.lifetime = aggregate(lifetimeRecords)
        }

        profile.recentGames = records.suffix(8).map { r in
            CoachingProfile.RecentGame(
                date: r.date, opening: r.opening ?? r.eco, accuracy: r.accuracy,
                result: r.playerResult, blunders: r.counts.blunder)
        }
        return profile
    }

    /// Convenience: build directly from a store. Resolves "me" via the injected identity.
    public static func buildProfile(
        playerID: String, store: HistoryStore, displayName: String? = nil
    ) -> CoachingProfile {
        buildProfile(playerID: playerID, records: store.loadRecords(), displayName: displayName)
    }

    // MARK: - Aggregation (port of `_aggregate`)

    static func aggregate(_ records: [GameRecord]) -> CoachingProfile.View {
        var view = CoachingProfile.View(
            window: nil, games: records.count, avgAccuracy: nil,
            results: .init(), mistakeTotals: .init(), mistakesPerGame: .init(),
            topMotifs: [], phaseLossTotal: .init(), weakestPhase: nil,
            bySpeed: [], openings: [])
        if records.isEmpty { return view }

        var accs: [Double] = []
        var results = CoachingProfile.ResultTally()
        var counts = CoachingProfile.MistakeTotals()
        var motifs: [String: Int] = [:]
        var phaseLoss = CoachingProfile.PhaseLossTotal()
        var openings: [String: (games: Int, accSum: Double)] = [:]
        var bySpeed: [String: (games: Int, accSum: Double, accN: Int, blunders: Int)] = [:]

        for r in records {
            accs.append(r.accuracy)
            switch r.playerResult {
            case "win": results.win += 1
            case "loss": results.loss += 1
            case "draw": results.draw += 1
            default: break
            }
            counts.inaccuracy += r.counts.inaccuracy
            counts.mistake += r.counts.mistake
            counts.blunder += r.counts.blunder
            phaseLoss.opening += r.phaseLoss.opening
            phaseLoss.middlegame += r.phaseLoss.middlegame
            phaseLoss.endgame += r.phaseLoss.endgame
            for m in r.mistakes {
                for motif in m.motifs { motifs[motif, default: 0] += 1 }
            }
            let op = r.opening ?? r.eco ?? "Unknown"
            var st = openings[op] ?? (0, 0)
            st.games += 1
            st.accSum += r.accuracy
            openings[op] = st

            let sp = r.speed.isEmpty ? "unknown" : r.speed
            var sps = bySpeed[sp] ?? (0, 0, 0, 0)
            sps.games += 1
            sps.accSum += r.accuracy
            sps.accN += 1
            sps.blunders += r.counts.blunder
            bySpeed[sp] = sps
        }

        let games = records.count
        view.avgAccuracy = accs.isEmpty ? nil : round1(accs.reduce(0, +) / Double(accs.count))
        view.results = results
        view.mistakeTotals = counts
        view.mistakesPerGame = CoachingProfile.MistakeRates(
            inaccuracy: round2(Double(counts.inaccuracy) / Double(games)),
            mistake: round2(Double(counts.mistake) / Double(games)),
            blunder: round2(Double(counts.blunder) / Double(games)))

        // Top motifs (most common first; ties broken by name for determinism), top 8.
        view.topMotifs = motifs
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(8)
            .map { CoachingProfile.MotifCount(motif: $0.key, count: $0.value) }

        view.phaseLossTotal = CoachingProfile.PhaseLossTotal(
            opening: round1(phaseLoss.opening),
            middlegame: round1(phaseLoss.middlegame),
            endgame: round1(phaseLoss.endgame))
        let phasePairs = [
            ("opening", phaseLoss.opening), ("middlegame", phaseLoss.middlegame),
            ("endgame", phaseLoss.endgame),
        ]
        view.weakestPhase = phasePairs.contains { $0.1 > 0 }
            ? phasePairs.max { $0.1 < $1.1 }?.0 : nil

        view.bySpeed = bySpeed
            .sorted { $0.value.games > $1.value.games }
            .map { kv in
                CoachingProfile.SpeedStat(
                    speed: kv.key, games: kv.value.games,
                    avgAccuracy: kv.value.accN > 0
                        ? round1(kv.value.accSum / Double(kv.value.accN)) : nil,
                    blundersPerGame: kv.value.games > 0
                        ? round2(Double(kv.value.blunders) / Double(kv.value.games)) : nil)
            }

        view.openings = openings
            .map { kv in
                CoachingProfile.OpeningStat(
                    opening: kv.key, games: kv.value.games,
                    avgAccuracy: kv.value.games > 0
                        ? round1(kv.value.accSum / Double(kv.value.games)) : nil)
            }
            .sorted { $0.games > $1.games }
            .prefix(10)
            .map { $0 }

        return view
    }

    // MARK: - Prompt formatting (port of `format_profile_for_prompt` + `_view_summary`)

    /// Render the hybrid profile as a compact coaching block for the chat prompt (nil if empty).
    public static func formatProfileForPrompt(_ profile: CoachingProfile) -> String? {
        guard let recent = profile.recent, recent.games > 0 else { return nil }
        var out = [
            "The user's play profile — use it to personalise advice and point out recurring "
            + "patterns when relevant (don't force it if it doesn't apply):"
        ]
        let scope = recent.window != nil
            ? "last \(recent.window!) games" : "all \(recent.games) games"
        out.append("- Recent form (\(scope)): \(viewSummary(recent)).")

        // Per-mode breakdown — only worth stating when more than one mode was played.
        let bySpeed = recent.bySpeed.filter { $0.speed != "unknown" }
        if bySpeed.count >= 2 {
            let parts = bySpeed.map { s -> String in
                let acc = s.avgAccuracy != nil ? "\(pct(s.avgAccuracy!))% acc" : "acc n/a"
                let blunders = s.blundersPerGame.map { g($0) } ?? "0"
                return "\(s.speed) ×\(s.games) (\(acc), \(blunders) blunders/game)"
            }
            out.append(
                "- By mode: " + parts.joined(separator: "; ") + ". Mistake tolerance differs by "
                + "mode — judge the current game against its own mode (faster time controls warrant "
                + "more lenient expectations).")
        }

        if let lifetime = profile.lifetime, lifetime.games > 0, lifetime.games != recent.games {
            out.append("- Lifetime (\(lifetime.games) games): \(viewSummary(lifetime)).")
            if let ra = recent.avgAccuracy, let la = lifetime.avgAccuracy, abs(ra - la) >= 2 {
                let trend = ra > la ? "improving" : "slipping"
                out.append(
                    "- Trend: \(trend) — recent accuracy \(pct(ra))% vs lifetime \(pct(la))%. "
                    + "Weight the recent form more heavily.")
            }
        }
        return out.joined(separator: "\n")
    }

    /// One-line summary of an aggregate view. Port of `_view_summary`.
    static func viewSummary(_ view: CoachingProfile.View) -> String {
        var bits: [String] = []
        if let acc = view.avgAccuracy {
            let r = view.results
            bits.append("accuracy \(pct(acc))% (\(r.win)W-\(r.loss)L-\(r.draw)D)")
        }
        if !view.topMotifs.isEmpty {
            let named = view.topMotifs.prefix(4).map {
                "\(Motifs.labels[$0.motif] ?? $0.motif) (×\($0.count))"
            }.joined(separator: ", ")
            bits.append("recurring: \(named)")
        }
        if let weakest = view.weakestPhase {
            bits.append("weakest phase \(weakest)")
        }
        return bits.joined(separator: "; ")
    }

    // MARK: - Weakness Report facts (plan U4)

    /// Compact facts payload for the Weakness Report's private, server-side
    /// prompt (`chesscoach-gateway`'s `/api/weaknessReport`, plan U3/KTD-3) --
    /// NOT the prompt itself, just the structured numbers the server needs.
    /// `nil` when there's no game data at all yet.
    public static func weaknessReportFacts(_ profile: CoachingProfile) -> WeaknessReportFacts? {
        guard let recent = profile.recent, recent.games > 0 else { return nil }
        return WeaknessReportFacts(
            topMotifs: recent.topMotifs.map { .init(motif: $0.motif, count: $0.count) },
            weakestPhase: recent.weakestPhase,
            recentAccuracy: recent.avgAccuracy,
            lifetimeAccuracy: profile.lifetime?.avgAccuracy,
            gamesAnalyzed: profile.gamesAnalyzed
        )
    }

    // MARK: - Helpers

    static func round1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }
    static func round2(_ x: Double) -> Double { (x * 100).rounded(.toNearestOrEven) / 100 }
    /// Percent display matching the source's float rendering (drops a trailing ".0").
    static func pct(_ x: Double) -> String {
        x == x.rounded() ? String(format: "%g", x) : String(x)
    }
    static func g(_ x: Double) -> String { String(format: "%g", x) }
}
