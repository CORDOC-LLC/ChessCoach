//  Lichess.swift
//  U11 — fetch games from the public Lichess API so users don't have to paste PGNs.
//  Port of `server/core/lichess.py`.
//
//  Two entry points, both returning data that flows straight into the analyser (the
//  `pgn` field carries Elo headers, a `Site` containing "lichess" so platform
//  normalisation works, and `[%clk]` comments so time-trouble motifs work):
//
//    - fetchUserGames(username:max:...) -> [GameSummary]  (newest first)
//    - fetchGame(idOrURL:)             -> GameSummary
//
//  Per the unit's plan we request PGN (not the source's NDJSON) and split it with the
//  existing `MultiPGN` facade. Auth is OPTIONAL: a Personal Access Token is throttled
//  per-token instead of per-IP. Public games need no token.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One game's metadata plus its full PGN (ready to hand to the analyser).
public struct GameSummary: Sendable, Equatable, Codable {
    public var gameID: String
    public var url: String
    public var white: String
    public var black: String
    public var whiteElo: Int?
    public var blackElo: Int?
    public var result: String
    public var speed: String
    public var opening: String?
    public var date: String?
    public var pgn: String

    public init(
        gameID: String, url: String, white: String, black: String,
        whiteElo: Int?, blackElo: Int?, result: String, speed: String,
        opening: String?, date: String?, pgn: String
    ) {
        self.gameID = gameID; self.url = url; self.white = white; self.black = black
        self.whiteElo = whiteElo; self.blackElo = blackElo; self.result = result
        self.speed = speed; self.opening = opening; self.date = date; self.pgn = pgn
    }
}

/// A user-facing problem talking to Lichess (network, bad id, rate limit, ...).
/// Mirrors the source `LichessError` with discrete, testable cases.
public enum LichessError: Error, Equatable, Sendable {
    case network(String)
    case badID
    case notFound
    case unauthorized
    case rateLimit
    case http(Int, String)
    case emptyResponse

    public var message: String {
        switch self {
        case .network(let detail):
            return "Could not reach Lichess: \(detail)"
        case .badID:
            return "A Lichess game id or URL is required."
        case .notFound:
            return "Lichess returned 404 — no such username or game id."
        case .unauthorized:
            return "Lichess rejected the token (HTTP 401) — check your access token."
        case .rateLimit:
            return "Lichess rate limit hit (HTTP 429). Wait about a minute and try again. "
                + "Heavy users can set a Personal Access Token (free, from "
                + "https://lichess.org/account/oauth/token) to be throttled per-token instead of per-IP."
        case .http(let code, let body):
            return "Lichess error (HTTP \(code)): \(body.prefix(200))"
        case .emptyResponse:
            return "Lichess returned no games."
        }
    }
}

/// Client for the public Lichess game-export API. URLSession and base URL are
/// injectable so tests can drive it with a mock `URLProtocol` and no real network.
public struct LichessClient: Sendable {

    /// Default cap on a user's recent games, matching the source `LICHESS_DEFAULT_MAX`.
    public static let defaultMax = 3

    let session: URLSession
    let baseURL: String
    let token: String?

    public init(session: URLSession = .shared, baseURL: String = "https://lichess.org", token: String? = nil) {
        self.session = session
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
    }

    // MARK: - Public API

    /// Fetch a user's most recent games (newest first) as `GameSummary` objects.
    ///
    /// `perf` is a comma-separated speed filter ("blitz,rapid"); `color` filters to
    /// games the user played as white/black; `sinceDays` limits to the last N days.
    public func fetchUserGames(
        username: String,
        max: Int? = nil,
        rated: Bool? = nil,
        perf: String? = nil,
        color: String? = nil,
        sinceDays: Int? = nil
    ) async throws -> [GameSummary] {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw LichessError.badID }
        let n = (max ?? 0) > 0 ? max! : Self.defaultMax

        var query: [URLQueryItem] = [
            .init(name: "max", value: String(n)),
            .init(name: "clocks", value: "true"),
            .init(name: "opening", value: "true"),
            .init(name: "sort", value: "dateDesc"),
        ]
        if let rated { query.append(.init(name: "rated", value: rated ? "true" : "false")) }
        if let perf, !perf.isEmpty { query.append(.init(name: "perfType", value: perf)) }
        if color == "white" || color == "black" { query.append(.init(name: "color", value: color)) }
        if let sinceDays, sinceDays > 0 {
            let ms = Int((Date().timeIntervalSince1970 - Double(sinceDays) * 86400) * 1000)
            query.append(.init(name: "since", value: String(ms)))
        }

        let text = try await get(
            path: "/api/games/user/\(name)", query: query, accept: "application/x-chess-pgn")
        return MultiPGN.splitPGN(text).map { summary(fromPGN: $0) }
    }

    /// Fetch a single game by its Lichess id or URL.
    public func fetchGame(idOrURL: String) async throws -> GameSummary {
        let gid = Self.extractGameID(idOrURL)
        guard !gid.isEmpty else { throw LichessError.badID }
        let text = try await get(
            path: "/game/export/\(gid)", query: [
                .init(name: "clocks", value: "true"),
                .init(name: "opening", value: "true"),
            ], accept: "application/x-chess-pgn")
        guard let pgn = MultiPGN.splitPGN(text).first else { throw LichessError.emptyResponse }
        return summary(fromPGN: pgn)
    }

    // MARK: - Request

    private func get(path: String, query: [URLQueryItem], accept: String) async throws -> String {
        guard var components = URLComponents(string: baseURL + path) else {
            throw LichessError.network("bad URL")
        }
        components.queryItems = query
        guard let url = components.url else { throw LichessError.network("bad URL") }

        var request = URLRequest(url: url)
        request.setValue("gemma-chess", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LichessError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            return String(decoding: data, as: UTF8.self)
        }
        let body = String(decoding: data, as: UTF8.self)
        switch http.statusCode {
        case 404: throw LichessError.notFound
        case 401: throw LichessError.unauthorized
        case 429: throw LichessError.rateLimit
        case let code where code >= 400: throw LichessError.http(code, body)
        default: return body
        }
    }

    // MARK: - Summary building

    func summary(fromPGN pgn: String) -> GameSummary {
        let h = MultiPGN.headers(ofPGN: pgn)
        let url = gameURL(h)
        let gid = url.flatMap { Self.extractGameID($0) } ?? Self.extractGameID(h["GameId"] ?? "")
        return GameSummary(
            gameID: gid,
            url: url ?? (gid.isEmpty ? "" : "\(baseURL)/\(gid)"),
            white: h["White"] ?? "?",
            black: h["Black"] ?? "?",
            whiteElo: intOrNil(h["WhiteElo"]),
            blackElo: intOrNil(h["BlackElo"]),
            result: h["Result"] ?? "*",
            speed: Evaluation.classifySpeed(timeControl: h["TimeControl"], event: h["Event"]).rawValue,
            opening: (h["Opening"]?.isEmpty == false) ? h["Opening"] : nil,
            date: cleanDate(h),
            pgn: pgn)
    }

    private func gameURL(_ headers: [String: String]) -> String? {
        for key in ["Site", "Link"] {
            let val = (headers[key] ?? "").trimmingCharacters(in: .whitespaces)
            if val.hasPrefix("http") { return val }
        }
        return nil
    }

    private func intOrNil(_ raw: String?) -> Int? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(s)
    }

    private func cleanDate(_ headers: [String: String]) -> String? {
        let raw = (headers["UTCDate"] ?? headers["Date"] ?? "").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || raw.contains("?") { return nil }
        return raw
    }

    /// Accept a bare id or a full Lichess URL (with optional /white, /black, #move
    /// suffixes). Port of `_extract_game_id`.
    static func extractGameID(_ raw: String) -> String {
        var gid = raw.trimmingCharacters(in: .whitespaces)
        gid = gid.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0].description
        gid = gid.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].description
        while gid.hasSuffix("/") { gid.removeLast() }
        if gid.contains("/") {
            let parts = gid.split(separator: "/").map(String.init)
                .filter { !$0.isEmpty && $0.lowercased() != "white" && $0.lowercased() != "black" }
            gid = parts.last ?? ""
        }
        // A game id is 8 chars; a full (12-char) id still starts with the public id.
        return String(gid.prefix(8))
    }
}
