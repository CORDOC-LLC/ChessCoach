//  HistoryStore.swift
//  U9 — persistent game history. Port of the record-building + storage parts of the
//  source `server/core/history.py`.
//
//  Each analysed game is turned into one compact `GameRecord` and appended to
//  `<base>/history/games.jsonl`. The JSONL is append-only; readers dedupe by keeping
//  the latest record per (gameID, reviewedSide) so a re-analysis supersedes the old
//  one. Records carry both the raw provenance (platform, playerName) and a resolved
//  canonical playerID, so one person's several accounts fold into one coaching profile.
//
//  Identity is injected (username + aliases) rather than read from a global config, so
//  the store has no hidden state and is trivially testable with a temp base dir.

import Foundation
import CryptoKit
import ChessKit

/// Schema version stamped on every record (bump on incompatible shape changes).
public let historySchemaVersion = 1

/// Injected "who is me" mapping: a canonical username plus alternate handles that fold
/// onto it. Port of the env / identities.json identity resolution in the source.
public struct PlayerIdentity: Sendable, Equatable {
    /// One alternate handle, optionally pinned to a platform ("lichess"/"chesscom").
    public struct Alias: Sendable, Equatable {
        public var name: String
        public var platform: String?
        public init(name: String, platform: String? = nil) {
            self.name = name; self.platform = platform
        }
    }

    public var username: String
    public var aliases: [Alias]

    public init(username: String = "", aliases: [Alias] = []) {
        self.username = username; self.aliases = aliases
    }
}

/// One analysed game as a compact, JSONL-ready coaching record. Mirrors the dict
/// returned by the source `build_game_record`.
public struct GameRecord: Codable, Sendable, Equatable {

    /// One flagged move within a record.
    public struct Mistake: Codable, Sendable, Equatable {
        public var ply: Int
        public var moveNumber: Int
        public var color: String
        public var san: String
        public var uci: String
        public var bestSan: String
        public var bestUci: String?
        public var classification: String
        public var winBefore: Double
        public var winAfter: Double
        public var winDrop: Double
        public var phase: String
        public var fenBefore: String
        public var clockAfter: Double?
        public var oppClock: Double?
        public var motifs: [String]
    }

    public struct Counts: Codable, Sendable, Equatable {
        public var inaccuracy: Int
        public var mistake: Int
        public var blunder: Int
        public init(inaccuracy: Int = 0, mistake: Int = 0, blunder: Int = 0) {
            self.inaccuracy = inaccuracy; self.mistake = mistake; self.blunder = blunder
        }
    }

    public struct PhaseLoss: Codable, Sendable, Equatable {
        public var opening: Double
        public var middlegame: Double
        public var endgame: Double
        public init(opening: Double = 0, middlegame: Double = 0, endgame: Double = 0) {
            self.opening = opening; self.middlegame = middlegame; self.endgame = endgame
        }
    }

    public var schemaVersion: Int
    public var gameID: String
    public var reviewedSide: String
    public var analyzedAt: String
    public var playerID: String
    public var platform: String
    public var playerName: String
    public var date: String?
    public var white: String
    public var black: String
    public var result: String
    public var playerResult: String?
    public var eco: String?
    public var opening: String?
    public var timeControl: String?
    public var speed: String
    public var playerElo: Int?
    public var opponentElo: Int?
    public var gameURL: String?
    public var pgn: String
    public var sweepDepth: Int?
    public var reviewElo: Double?
    public var thresholds: [Double]?
    public var plyCount: Int
    public var accuracy: Double
    public var counts: Counts
    public var phaseLoss: PhaseLoss
    public var mistakes: [Mistake]
}

/// Persistent game history. Port of the storage layer of `server/core/history.py`.
public struct HistoryStore: Sendable {

    /// Base directory holding `history/games.jsonl`. Injectable so tests can point at a
    /// temp dir; defaults to Application Support/GemmaChess.
    public let baseDir: URL

    public init(baseDir: URL? = nil) {
        self.baseDir = baseDir ?? Self.defaultBaseDir
    }

    static var defaultBaseDir: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GemmaChess", isDirectory: true)
    }

    var historyPath: URL {
        baseDir.appendingPathComponent("history/games.jsonl")
    }

    // MARK: - Identity resolution

    /// Normalise any platform spelling to a token. Port of `_norm_platform`.
    static func normPlatform(_ raw: String?) -> String {
        let s = (raw ?? "").lowercased()
        if s.contains("lichess") { return "lichess" }
        if s.contains("chess.com") || s.contains("chesscom") { return "chesscom" }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    static func platformFromHeaders(_ headers: [String: String]) -> String {
        let blob = ["Site", "Link", "Event"].map { headers[$0] ?? "" }.joined(separator: " ")
        return normPlatform(blob)
    }

    /// Resolve (playerID, platform, playerName) for the reviewed side. The canonical
    /// playerID comes from the injected identity (username/aliases) when a handle
    /// matches; otherwise it falls back to the raw handle so unmapped accounts are
    /// still recorded, never merged by accident. Port of `resolve_identity`.
    public static func resolveIdentity(
        headers: [String: String], reviewedSide: String, identity: PlayerIdentity
    ) -> (playerID: String, platform: String, playerName: String) {
        let nameKey = reviewedSide == "white" ? "White" : "Black"
        let name = (headers[nameKey] ?? "").trimmingCharacters(in: .whitespaces)
        let platform = platformFromHeaders(headers)
        let nameLC = name.lowercased()

        if !nameLC.isEmpty && !identity.username.isEmpty {
            if nameLC == identity.username.lowercased() {
                return (identity.username, platform, name)
            }
            for alias in identity.aliases {
                if alias.name.lowercased() == nameLC
                    && (alias.platform == nil || normPlatform(alias.platform) == platform) {
                    return (identity.username, platform, name)
                }
            }
        }

        let fallback = !nameLC.isEmpty
            ? nameLC
            : (identity.username.isEmpty ? "me" : identity.username.lowercased())
        return (fallback, platform, name)
    }

    // MARK: - Phase

    /// opening / middlegame / endgame from material + move number. Port of `_phase`.
    static func phase(fen: String, moveNumber: Int) -> String {
        guard let board = Position(fen: fen) else { return "middlegame" }
        let pieces = board.pieces.filter { $0.kind != .king && $0.kind != .pawn }
        let queens = pieces.filter { $0.kind == .queen }.count
        if pieces.count <= 6 || (queens == 0 && pieces.count <= 8) { return "endgame" }
        if moveNumber <= 12 { return "opening" }
        return "middlegame"
    }

    // MARK: - Record building

    /// Turn a `ReviewSession` into one JSONL-ready coaching record. Port of `build_game_record`.
    public func buildGameRecord(from session: ReviewSession, identity: PlayerIdentity) -> GameRecord {
        let headers = session.headers
        let side = session.player
        let (playerID, platform, playerName) = Self.resolveIdentity(
            headers: headers, reviewedSide: side, identity: identity)

        let base = Evaluation.timeControlClock(headers["TimeControl"])?.base
        var counts = GameRecord.Counts()
        var phaseLoss = GameRecord.PhaseLoss()
        var mistakes: [GameRecord.Mistake] = []

        for m in session.mistakes {
            let bestUCI = m.bestLineUCI.first
            let phase = Self.phase(fen: m.fenBefore, moveNumber: m.moveNumber)
            switch m.classification {
            case "inaccuracy": counts.inaccuracy += 1
            case "mistake": counts.mistake += 1
            case "blunder": counts.blunder += 1
            default: break
            }
            switch phase {
            case "opening": phaseLoss.opening += m.winSwing
            case "endgame": phaseLoss.endgame += m.winSwing
            default: phaseLoss.middlegame += m.winSwing
            }
            var motifs = Motifs.tagMotifs(
                fenBefore: m.fenBefore, moveUCI: m.moveUCI, bestUCI: bestUCI,
                winSwing: m.winSwing, evalBefore: m.evalBefore)
            motifs += Motifs.timeMotifs(clockAfter: m.clockAfter, oppClock: m.oppClock, base: base)
            mistakes.append(
                GameRecord.Mistake(
                    ply: m.ply, moveNumber: m.moveNumber, color: m.color,
                    san: m.moveSAN, uci: m.moveUCI, bestSan: m.bestMoveSAN, bestUci: bestUCI,
                    classification: m.classification,
                    winBefore: Self.round1(m.winBefore), winAfter: Self.round1(m.winAfter),
                    winDrop: Self.round1(m.winSwing), phase: phase, fenBefore: m.fenBefore,
                    clockAfter: m.clockAfter, oppClock: m.oppClock, motifs: motifs))
        }

        let timelinePlies = max(session.timeline.count - 1, 0)
        let plies = timelinePlies != 0 ? timelinePlies : session.allMoves.count
        let accuracy = side == "white" ? session.accuracyWhite : session.accuracyBlack

        // Opening/ECO: trust PGN headers, fall back to a local lookup over timeline FENs.
        var eco = (headers["ECO"]?.isEmpty == false) ? headers["ECO"] : nil
        var opening = (headers["Opening"]?.isEmpty == false) ? headers["Opening"] : nil
        if opening == nil {
            let fens = session.timeline.map { $0.fen }
            if let classified = Openings.classifyFromFens(fens) {
                eco = eco ?? classified.eco
                opening = classified.name
            }
        }

        let speed = Evaluation.classifySpeed(
            timeControl: headers["TimeControl"], event: headers["Event"])

        return GameRecord(
            schemaVersion: historySchemaVersion,
            gameID: Self.gameID(session),
            reviewedSide: side,
            analyzedAt: Self.nowISO(),
            playerID: playerID,
            platform: platform,
            playerName: playerName,
            date: Self.cleanDate(headers),
            white: headers["White"] ?? "?",
            black: headers["Black"] ?? "?",
            result: session.result,
            playerResult: Self.playerResult(session.result, side: side),
            eco: eco,
            opening: opening,
            timeControl: (headers["TimeControl"]?.isEmpty == false) ? headers["TimeControl"] : nil,
            speed: speed.rawValue,
            playerElo: Self.intOrNil(headers[side == "white" ? "WhiteElo" : "BlackElo"]),
            opponentElo: Self.intOrNil(headers[side == "white" ? "BlackElo" : "WhiteElo"]),
            gameURL: Self.gameURL(headers),
            pgn: session.pgn,
            sweepDepth: session.sweepDepth,
            reviewElo: session.reviewElo,
            thresholds: session.thresholds,
            plyCount: plies,
            accuracy: Self.round1(accuracy),
            counts: counts,
            phaseLoss: GameRecord.PhaseLoss(
                opening: Self.round1(phaseLoss.opening),
                middlegame: Self.round1(phaseLoss.middlegame),
                endgame: Self.round1(phaseLoss.endgame)),
            mistakes: mistakes)
    }

    // MARK: - Storage

    /// Append the game to history. Returns the record. Port of `record_game` (minus
    /// the profile-cache write, which `CoachingProfile` rebuilds on demand).
    @discardableResult
    public func recordGame(_ session: ReviewSession, identity: PlayerIdentity) -> GameRecord {
        let record = buildGameRecord(from: session, identity: identity)
        appendRecord(record)
        return record
    }

    func appendRecord(_ record: GameRecord) {
        let path = historyPath
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(record),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.data(using: .utf8)?.write(to: path)
        }
    }

    /// All games, deduped to the latest record per (gameID, reviewedSide). Optionally
    /// filtered to one playerID. Bad/blank lines are skipped. Port of `load_records`.
    public func loadRecords(playerID: String? = nil) -> [GameRecord] {
        guard let text = try? String(contentsOf: historyPath, encoding: .utf8) else { return [] }
        var latest: [String: GameRecord] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let rec = try? Self.decoder.decode(GameRecord.self, from: Data(line.utf8)) else {
                continue
            }
            let key = "\(rec.gameID)\u{1}\(rec.reviewedSide)"
            if let prev = latest[key], rec.analyzedAt < prev.analyzedAt { continue }
            latest[key] = rec
        }
        var records = Array(latest.values)
        if let playerID { records = records.filter { $0.playerID == playerID } }
        return records
    }

    /// Compact, newest-first list of analysed games. Port of `history_rows` (returns
    /// the full records here; the UI projects whatever columns it needs).
    public func historyRows(playerID: String? = nil) -> [GameRecord] {
        loadRecords(playerID: playerID).sorted { $0.analyzedAt > $1.analyzedAt }
    }

    /// Distinct playerIDs present in history. Port of `list_players`.
    public func listPlayers() -> [String] {
        Array(Set(loadRecords().map { $0.playerID })).sorted()
    }

    // MARK: - Helpers

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    static let decoder = JSONDecoder()

    static func gameID(_ session: ReviewSession) -> String {
        let fromTimeline = session.timeline.compactMap { $0.moveUCI }
        let ucis = fromTimeline.isEmpty ? session.allMoves.map { $0.moveUCI } : fromTimeline
        let digest = Insecure.SHA1.hash(data: Data(ucis.joined().utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    static func intOrNil(_ raw: String?) -> Int? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(s)
    }

    static func cleanDate(_ headers: [String: String]) -> String? {
        let raw = (headers["UTCDate"] ?? headers["Date"] ?? "").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || raw.contains("?") { return nil }
        return raw.replacingOccurrences(of: ".", with: "-")
    }

    static func playerResult(_ result: String, side: String) -> String? {
        switch result {
        case "1-0": return side == "white" ? "win" : "loss"
        case "0-1": return side == "black" ? "win" : "loss"
        case "1/2-1/2": return "draw"
        default: return nil
        }
    }

    static func gameURL(_ headers: [String: String]) -> String? {
        for key in ["Site", "Link"] {
            let val = (headers[key] ?? "").trimmingCharacters(in: .whitespaces)
            if val.hasPrefix("http") { return val }
        }
        return nil
    }

    /// Round to 1 decimal (round-half-to-even), matching Python's `round(x, 1)`.
    static func round1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }
}
