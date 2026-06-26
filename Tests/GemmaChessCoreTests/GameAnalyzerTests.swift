//  GameAnalyzerTests.swift
//  U7 — full-game sweep. These spin up real Stockfish, so they run serialized at a
//  shallow depth (12) to stay fast.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("GameAnalyzer", .serialized)
struct GameAnalyzerTests {

    static func pgn(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "pgn", subdirectory: "Fixtures/pgns"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Thread-safe collector for the @Sendable progress callback.
    final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(Int, Int)] = []
        func record(_ done: Int, _ total: Int) { lock.lock(); items.append((done, total)); lock.unlock() }
        var last: (Int, Int)? { lock.lock(); defer { lock.unlock() }; return items.last }
        var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    }

    @Test("game1 reviewed as White: a flagged blunder, lower White accuracy, full timeline")
    func game1AsWhite() async throws {
        let pgn = try Self.pgn("game1")
        let progress = ProgressBox()
        let session = try await GameAnalyzer.analyzeGame(
            pgn: pgn, player: "white", depth: 12,
            onProgress: { done, total in progress.record(done, total) })

        // 1. f3 e5 2. g4 Qh4# -> 4 plies, 5 timeline nodes (positions 0..4).
        #expect(session.timeline.count == 5)
        #expect(session.player == "white")
        #expect(session.result == "0-1")

        // White blundered (2.g4?? allows mate), so there is at least one flagged blunder.
        let blunders = session.mistakes.filter { $0.classification == "blunder" }
        #expect(!blunders.isEmpty)
        #expect(session.mistakes.allSatisfy { $0.color == "white" })

        // White played the losing side -> lower accuracy than Black.
        #expect(session.accuracyWhite < session.accuracyBlack)

        // mistake_index links: every flagged mistake's ply resolves back through the timeline.
        for (i, m) in session.mistakes.enumerated() {
            let node = try #require(session.timeline.first { $0.ply == m.ply })
            #expect(node.mistakeIndex == i)
            #expect(node.classification == m.classification)
            // node_index convention: the timeline node whose outgoing move is this mistake.
            #expect(session.timeline[m.ply - 1].moveUCI == m.moveUCI)
        }

        // The flagged blunder carries an engine-grounded comment.
        let blunder = try #require(blunders.first)
        #expect(blunder.comment.contains("Win chance"))
        #expect(!blunder.bestLineSAN.isEmpty)

        // Progress fired once per evaluated position, ending at (total, total).
        #expect(progress.count == 5)
        #expect(progress.last?.0 == 5)
        #expect(progress.last?.1 == 5)
    }

    @Test("reviewing the non-blundering side yields no mistakes for that side")
    func game1AsBlack() async throws {
        let pgn = try Self.pgn("game1")
        let session = try await GameAnalyzer.analyzeGame(pgn: pgn, player: "black", depth: 12)
        // Black delivered mate (a clean, short, winning game) -> no flagged Black mistakes.
        #expect(session.mistakes.isEmpty)
        #expect(session.allMoves.allSatisfy { $0.color == "black" })
        #expect(session.timeline.count == 5)
    }

    @Test("auto player resolves from username against the PGN headers")
    func autoResolvesUsername() async throws {
        let pgn = try Self.pgn("game1")
        // "tester" is White in game1.
        let session = try await GameAnalyzer.analyzeGame(
            pgn: pgn, player: "auto", depth: 12, username: "tester")
        #expect(session.player == "white")
    }
}
