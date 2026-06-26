//  CoachingProfileTests.swift
//  U10 — aggregation + prompt formatting over synthetic GameRecords (no engine/disk).

import Testing
@testable import GemmaChessCore

@Suite("CoachingProfile")
struct CoachingProfileTests {

    /// Build a synthetic record with the fields aggregation cares about.
    static func record(
        id: String, at: String, accuracy: Double, result: String, speed: String,
        counts: GameRecord.Counts, phaseLoss: GameRecord.PhaseLoss = .init(),
        motifs: [String] = [], opening: String? = "Test Opening", playerID: String = "me"
    ) -> GameRecord {
        let mistakes = motifs.map {
            GameRecord.Mistake(
                ply: 1, moveNumber: 1, color: "white", san: "?", uci: "e2e4", bestSan: "?",
                bestUci: nil, classification: "blunder", winBefore: 60, winAfter: 40, winDrop: 20,
                phase: "middlegame", fenBefore: "x", clockAfter: nil, oppClock: nil, motifs: [$0])
        }
        return GameRecord(
            schemaVersion: 1, gameID: id, reviewedSide: "white", analyzedAt: at, playerID: playerID,
            platform: "lichess", playerName: "me", date: "2026-06-0\(id)", white: "me", black: "opp",
            result: result, playerResult: result, eco: nil, opening: opening, timeControl: "300+0",
            speed: speed, playerElo: 1500, opponentElo: 1500, gameURL: nil, pgn: "", sweepDepth: 16,
            reviewElo: nil, thresholds: nil, plyCount: 40, accuracy: accuracy, counts: counts,
            phaseLoss: phaseLoss, mistakes: mistakes)
    }

    @Test("aggregate accuracy, mistake rates, motifs, by-speed and weakest phase")
    func aggregate() {
        let records = [
            Self.record(id: "1", at: "2026-01-01T00:00:00Z", accuracy: 80, result: "win", speed: "blitz",
                   counts: .init(inaccuracy: 1, mistake: 1, blunder: 1),
                   phaseLoss: .init(opening: 5, middlegame: 10, endgame: 1),
                   motifs: ["hung_piece", "back_rank"]),
            Self.record(id: "2", at: "2026-01-02T00:00:00Z", accuracy: 90, result: "loss", speed: "blitz",
                   counts: .init(inaccuracy: 1, mistake: 0, blunder: 1),
                   phaseLoss: .init(opening: 2, middlegame: 20, endgame: 0),
                   motifs: ["hung_piece"]),
            Self.record(id: "3", at: "2026-01-03T00:00:00Z", accuracy: 70, result: "draw", speed: "rapid",
                   counts: .init(inaccuracy: 0, mistake: 2, blunder: 0),
                   phaseLoss: .init(opening: 1, middlegame: 3, endgame: 2),
                   motifs: ["pawn_grab"]),
        ]
        let profile = CoachingProfileBuilder.buildProfile(playerID: "me", records: records)
        let recent = try! #require(profile.recent)

        #expect(recent.games == 3)
        #expect(recent.avgAccuracy == 80.0)                       // (80+90+70)/3
        #expect(recent.results == .init(win: 1, loss: 1, draw: 1))
        #expect(recent.mistakeTotals == .init(inaccuracy: 2, mistake: 3, blunder: 2))
        #expect(recent.mistakesPerGame.blunder == 0.67)            // 2/3 rounded
        // hung_piece appears twice -> top motif.
        #expect(recent.topMotifs.first?.motif == "hung_piece")
        #expect(recent.topMotifs.first?.count == 2)
        // middlegame loss (33) dominates opening (8) and endgame (3).
        #expect(recent.weakestPhase == "middlegame")
        // Two speeds partitioned; blitz has 2 games, rapid 1.
        let blitz = try! #require(recent.bySpeed.first { $0.speed == "blitz" })
        let rapid = try! #require(recent.bySpeed.first { $0.speed == "rapid" })
        #expect(blitz.games == 2)
        #expect(rapid.games == 1)
        #expect(blitz.blundersPerGame == 1.0)                      // 2 blunders / 2 games
    }

    @Test("formatProfileForPrompt: nil when empty, text + trend when populated")
    func formatting() {
        // Empty -> nil.
        let empty = CoachingProfileBuilder.buildProfile(playerID: "me", records: [])
        #expect(CoachingProfileBuilder.formatProfileForPrompt(empty) == nil)

        // Older games weak (60%), newest two strong (95%); a small recent window makes
        // recent != lifetime so the improving trend is emitted.
        let records = [
            Self.record(id: "1", at: "2026-01-01T00:00:00Z", accuracy: 60, result: "loss", speed: "blitz",
                   counts: .init(blunder: 2), motifs: ["hung_piece"]),
            Self.record(id: "2", at: "2026-01-02T00:00:00Z", accuracy: 60, result: "loss", speed: "rapid",
                   counts: .init(blunder: 2), motifs: ["back_rank"]),
            Self.record(id: "3", at: "2026-01-03T00:00:00Z", accuracy: 95, result: "win", speed: "blitz",
                   counts: .init(blunder: 0), motifs: []),
            Self.record(id: "4", at: "2026-01-04T00:00:00Z", accuracy: 95, result: "win", speed: "rapid",
                   counts: .init(blunder: 0), motifs: []),
        ]
        let profile = CoachingProfileBuilder.buildProfile(
            playerID: "me", records: records, recentWindow: 2, lifetime: nil)
        let text = try! #require(CoachingProfileBuilder.formatProfileForPrompt(profile))
        #expect(text.contains("Recent form"))
        #expect(text.contains("By mode"))      // blitz + rapid both present
        #expect(text.contains("Lifetime"))
        #expect(text.contains("improving"))    // recent 95% vs lifetime 77.5%
    }
}
