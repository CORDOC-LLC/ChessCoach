//  AnalysisCacheTests.swift
//  U8 — disk cache. Engine-free: store a hand-built session and read it back.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite(.serialized)
struct AnalysisCacheTests {

    static let pgn = "1. f3 e5 2. g4 Qh4# 0-1"

    /// A minimal session whose timeline carries the game's UCI moves, so the cache can
    /// derive a stable game_id from it.
    static func session(player: String = "white") -> ReviewSession {
        ReviewSession(
            pgn: pgn,
            player: player,
            headers: ["White": "tester", "Black": "opponent", "Result": "0-1"],
            result: "0-1",
            speed: "blitz",
            accuracyWhite: 10,
            accuracyBlack: 90,
            sweepDepth: 16,
            timeline: [
                TimelineNode(node: 0, fen: "a", winWhite: 50, color: "white", moveNumber: 1,
                             ply: 1, moveSAN: "f3", moveUCI: "f2f3"),
                TimelineNode(node: 1, fen: "b", winWhite: 48, color: "black", moveNumber: 1,
                             ply: 2, moveSAN: "e5", moveUCI: "e7e5"),
                TimelineNode(node: 2, fen: "c", winWhite: 49, color: "white", moveNumber: 2,
                             ply: 3, moveSAN: "g4", moveUCI: "g2g4"),
                TimelineNode(node: 3, fen: "d", winWhite: 0, color: "black", moveNumber: 2,
                             ply: 4, moveSAN: "Qh4#", moveUCI: "d8h4"),
                TimelineNode(node: 4, fen: "e", winWhite: 0, color: "white", moveNumber: 3),
            ])
    }

    @Test("store then load returns an equal session")
    func storeLoad() throws {
        let original = Self.session()
        AnalysisCache.store(original)
        let loaded = try #require(AnalysisCache.load(pgn: Self.pgn, player: "white"))
        #expect(loaded == original)
        // Clean up the cache file we wrote.
        if let path = AnalysisCache.path(
            gameID: AnalysisCache.gameID(["f2f3", "e7e5", "g2g4", "d8h4"]), side: "white") {
            try? FileManager.default.removeItem(at: path)
        }
    }

    @Test("load resolves the auto side from the PGN headers")
    func loadAuto() throws {
        let original = Self.session()
        AnalysisCache.store(original)
        // "tester" is White; auto with that username resolves to the white-stored entry.
        let loaded = try #require(
            AnalysisCache.load(pgn: Self.pgn, player: "auto", username: "tester"))
        #expect(loaded.player == "white")
        if let path = AnalysisCache.path(
            gameID: AnalysisCache.gameID(["f2f3", "e7e5", "g2g4", "d8h4"]), side: "white") {
            try? FileManager.default.removeItem(at: path)
        }
    }

    @Test("a corrupt cache file is a miss, not a throw")
    func corruptFileMiss() throws {
        let ucis = ["f2f3", "e7e5", "g2g4", "d8h4"]
        let path = try #require(AnalysisCache.path(gameID: AnalysisCache.gameID(ucis), side: "white"))
        let dir = try #require(AnalysisCache.cacheDir())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json {{{".utf8).write(to: path)
        let loaded = AnalysisCache.load(pgn: Self.pgn, player: "white")
        #expect(loaded == nil)
        try? FileManager.default.removeItem(at: path)
    }

    @Test("missing entry returns nil")
    func missReturnsNil() {
        // A PGN we never stored.
        let other = "1. e4 c5 0-1"
        // Ensure no stale file from a prior run.
        if let path = AnalysisCache.path(gameID: AnalysisCache.gameID(["e2e4", "c7c5"]), side: "white") {
            try? FileManager.default.removeItem(at: path)
        }
        #expect(AnalysisCache.load(pgn: other, player: "white") == nil)
    }
}
