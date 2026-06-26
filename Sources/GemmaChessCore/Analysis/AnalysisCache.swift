//  AnalysisCache.swift
//  U8 — disk cache of fully-analysed games, so reopening a past game is instant.
//
//  A full `ReviewSession` is expensive to compute (a Stockfish sweep) but cheap to store
//  (~tens of KB of JSON). We persist each session under Application Support keyed by the
//  same `(game_id, reviewed_side)` pair the source dedupes on, where
//  `game_id = sha1(joined UCI move list)[:16]`. `load` recomputes that key straight from a
//  PGN — before any analysis — and short-circuits the sweep.
//
//  Everything is best-effort and engine-free: any failure (corrupt file, schema bump, disk
//  error) is swallowed and the caller falls back to a fresh sweep. The entry count is bounded
//  (least-recently-used pruned) so disk use stays in check.

import Foundation
import CryptoKit
import ChessKit

/// Disk cache for analysed `ReviewSession`s. Port of `server/core/analysis_cache.py`.
public enum AnalysisCache {

    /// Bump when the on-disk payload shape changes incompatibly, so stale files are ignored.
    static let cacheVersion = 1
    /// Keep at most this many entries, dropping least-recently-used first.
    static let cap = 200

    /// On-disk payload wrapper.
    struct Payload: Codable {
        var version: Int
        var side: String
        var sweepDepth: Int?
        var session: ReviewSession
    }

    // MARK: Paths / keys

    static func cacheDir() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return base.appendingPathComponent("GemmaChess/analysis-cache", isDirectory: true)
    }

    static func safe(_ part: String) -> String {
        let cleaned = part.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-") ? ch : "_"
        }
        let collapsed = String(cleaned).replacingOccurrences(
            of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "x" : trimmed
    }

    static func path(gameID: String, side: String) -> URL? {
        cacheDir()?.appendingPathComponent("\(safe(gameID))_\(safe(side)).json")
    }

    /// sha1 of the concatenated UCI move list, first 16 hex chars.
    public static func gameID(_ ucis: [String]) -> String {
        let digest = Insecure.SHA1.hash(data: Data(ucis.joined().utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// Every move (both sides) of the session, mirroring the source key derivation.
    static func sessionUCIs(_ sess: ReviewSession) -> [String] {
        let fromTimeline = sess.timeline.compactMap { $0.moveUCI }
        return fromTimeline.isEmpty ? sess.allMoves.map { $0.moveUCI } : fromTimeline
    }

    // MARK: Public API

    /// Persist a fully-analysed session to disk. Best-effort: never throws.
    public static func store(_ sess: ReviewSession) {
        let ucis = sessionUCIs(sess)
        guard !ucis.isEmpty,
              let path = path(gameID: gameID(ucis), side: sess.player),
              let dir = cacheDir()
        else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = Payload(
                version: cacheVersion, side: sess.player, sweepDepth: sess.sweepDepth, session: sess)
            let data = try JSONEncoder().encode(payload)
            let tmp = path.appendingPathExtension("tmp")
            try data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(path, withItemAt: tmp)
            if FileManager.default.fileExists(atPath: tmp.path) {
                // replaceItemAt failed to consume tmp (e.g. no existing file); move manually.
                try? FileManager.default.removeItem(at: path)
                try? FileManager.default.moveItem(at: tmp, to: path)
            }
            prune()
        } catch {
            // Caching must never break a review.
        }
    }

    /// Return a cached session for this PGN+side, or nil if not cached / unreadable.
    /// A corrupt or schema-mismatched file is treated as a miss (no throw).
    public static func load(pgn: String, player: String = "auto", username: String = "", aliases: [String] = []) -> ReviewSession? {
        guard let parsed = try? Game(pgn: pgn) else { return nil }
        let headers = MultiPGN.headers(ofPGN: pgn)
        let side = GameAnalyzer.resolvePlayer(headers: headers, player: player, username: username, aliases: aliases)

        let mainline = parsed.moves.indices
            .filter { $0.variation == MoveTree.Index.mainVariation }
            .sorted()
        let ucis = mainline.compactMap { parsed.moves[$0]?.lan }
        guard !ucis.isEmpty, let path = path(gameID: gameID(ucis), side: side) else { return nil }
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        do {
            let data = try Data(contentsOf: path)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == cacheVersion else { return nil }
            var sess = payload.session
            // Fresh open: drop any saved navigation state.
            sess.currentIndex = 0
            sess.exploreFen = nil
            // Mark as recently used for LRU pruning.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
            return sess
        } catch {
            return nil  // a bad cache file just means "miss"
        }
    }

    // MARK: Pruning

    static func prune() {
        guard cap > 0, let dir = cacheDir() else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
        else { return }
        let entries = names.filter { $0.pathExtension == "json" }
        guard entries.count > cap else { return }
        let sorted = entries.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da < db  // oldest first
        }
        for url in sorted.prefix(entries.count - cap) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
