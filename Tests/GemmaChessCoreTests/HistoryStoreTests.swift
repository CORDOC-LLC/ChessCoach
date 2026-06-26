//  HistoryStoreTests.swift
//  U9 — record building, JSONL persistence, dedupe, and identity folding.
//  The engine-backed test runs serialized at a shallow depth (12); the rest is pure.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("HistoryStore", .serialized)
struct HistoryStoreTests {

    /// A throwaway base dir, cleaned up after the closure runs.
    static func withTempStore(_ body: (HistoryStore) async throws -> Void) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GemmaChessTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(HistoryStore(baseDir: dir))
    }

    static func pgn(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "pgn", subdirectory: "Fixtures/pgns"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("build a record from a real analysis, persist it, read it back; re-analysis dedupes")
    func buildRecordAndDedupe() async throws {
        try await Self.withTempStore { store in
            let session = try await GameAnalyzer.analyzeGame(
                pgn: Self.pgn("game1"), player: "white", depth: 12)
            let identity = PlayerIdentity(username: "me", aliases: [.init(name: "tester")])

            let record = store.buildGameRecord(from: session, identity: identity)
            #expect(record.reviewedSide == "white")
            #expect(record.playerID == "me")          // "tester" folds onto the canonical id
            #expect(record.white == "tester")
            #expect(record.result == "0-1")
            #expect(!record.gameID.isEmpty)
            #expect(record.schemaVersion == historySchemaVersion)
            // White blundered 2.g4?? allowing mate, so there's at least one flagged move.
            #expect(!record.mistakes.isEmpty)

            store.recordGame(session, identity: identity)
            #expect(store.historyRows().count == 1)

            // Re-analysing the same game+side supersedes; the count stays at 1.
            store.recordGame(session, identity: identity)
            let rows = store.historyRows()
            #expect(rows.count == 1)
            #expect(rows.first?.playerID == "me")
        }
    }

    @Test("two aliases fold into one playerID")
    func identityFolds() async throws {
        try await Self.withTempStore { store in
            let identity = PlayerIdentity(
                username: "me", aliases: [.init(name: "alpha"), .init(name: "beta")])

            store.recordGame(Self.fakeSession(white: "alpha", uci: "e2e4"), identity: identity)
            store.recordGame(Self.fakeSession(white: "beta", uci: "d2d4"), identity: identity)

            #expect(store.listPlayers() == ["me"])
            #expect(store.loadRecords(playerID: "me").count == 2)
        }
    }

    @Test("resolveIdentity keys an unmapped handle by its own lowercased name")
    func unmappedIdentity() {
        let (pid, platform, name) = HistoryStore.resolveIdentity(
            headers: ["White": "Stranger", "Site": "https://lichess.org/abcd"],
            reviewedSide: "white", identity: PlayerIdentity(username: "me"))
        #expect(pid == "stranger")
        #expect(platform == "lichess")
        #expect(name == "Stranger")
    }

    /// A minimal hand-built session (no engine) with a distinct single move so its
    /// gameID is unique. Enough to exercise record building + identity resolution.
    static func fakeSession(white: String, uci: String) -> ReviewSession {
        let move = MoveReview(
            ply: 1, moveNumber: 1, color: "white", moveSAN: "?", moveUCI: uci,
            fenBefore: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            fenAfter: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1",
            evalBefore: 0, evalAfter: 0, winBefore: 50, winAfter: 50, winSwing: 0,
            classification: "best", bestMoveSAN: "?", bestLineUCI: [uci], bestLineSAN: ["?"],
            accuracy: 100)
        return ReviewSession(
            pgn: "[White \"\(white)\"]\n1. e4 *",
            player: "white",
            headers: ["White": white, "Black": "opp", "Result": "1-0", "TimeControl": "300+0"],
            result: "1-0", speed: "blitz",
            accuracyWhite: 90, accuracyBlack: 85,
            allMoves: [move], mistakes: [])
    }
}
