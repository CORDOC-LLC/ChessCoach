//  GameImportClient.swift
//  U4 — PGN import: pasted/uploaded text, or a public account's game history from
//  Chess.com or Lichess. Both platforms' game-history endpoints are free, public,
//  unauthenticated reads with no ChessCoach backend involved, so this whole feature
//  is free-tier (see docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md,
//  KTD-4).
//
//  All three entry points end in the same place: an array of individual, importable
//  PGN strings via the existing `MultiPGN.splitPGN` -- no new parsing logic here, and
//  no parallel history/analysis pipeline. Lichess fetching is delegated to the
//  existing `LichessClient` (`Import/Lichess.swift`), which already does exactly this
//  for a single account; Chess.com has no existing client, so this file adds one.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A user-facing problem importing from an account (Chess.com or Lichess).
/// Deliberately distinguishes "no such user" from "couldn't reach the server" --
/// the former means the username is wrong, the latter means try again later.
public enum GameImportError: Error, Equatable, Sendable {
    /// The platform reported no such username (HTTP 404). Distinct from "the
    /// username exists but has zero public games", which is not an error --
    /// see `GameImportClient.importAccount`.
    case userNotFound
    /// Couldn't reach the server at all: offline, timed out, DNS failure, etc.
    case network(String)
    /// The server responded, but with a non-2xx/404 status.
    case http(Int, String)

    public var message: String {
        switch self {
        case .userNotFound:
            return "No public games found for that username. Double-check the spelling."
        case .network(let detail):
            return "Could not reach the server: \(detail)"
        case .http(let code, let body):
            return "Server error (HTTP \(code)): \(body.prefix(200))"
        }
    }
}

/// Imports a pasted PGN blob or a public account's game history into individual,
/// analysis-ready PGN strings. `URLSession` is injectable so tests can drive both
/// platforms' network paths with a mock `URLProtocol` and no real network.
public struct GameImportClient: Sendable {

    /// Which platform's public game-history endpoint to fetch.
    public enum Platform: String, Sendable, CaseIterable, Identifiable {
        case chessCom
        case lichess

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .chessCom: return "Chess.com"
            case .lichess: return "Lichess"
            }
        }
    }

    /// Chess.com's monthly archives are returned oldest-first; capping how many of
    /// the most recent months we walk keeps a long-lived account's import from
    /// firing an unbounded number of requests. Generous enough to cover a very
    /// active player's last several months.
    public static let defaultMaxArchives = 6

    /// How many recent games to pull from Lichess (that API is a single paged
    /// request, not one-request-per-month like Chess.com).
    public static let defaultLichessMax = 100

    let session: URLSession
    let chessComBaseURL: String
    let lichessBaseURL: String
    let lichessToken: String?

    public init(
        session: URLSession = .shared,
        chessComBaseURL: String = "https://api.chess.com",
        lichessBaseURL: String = "https://lichess.org",
        lichessToken: String? = nil
    ) {
        self.session = session
        self.chessComBaseURL = chessComBaseURL.hasSuffix("/") ? String(chessComBaseURL.dropLast()) : chessComBaseURL
        self.lichessBaseURL = lichessBaseURL.hasSuffix("/") ? String(lichessBaseURL.dropLast()) : lichessBaseURL
        self.lichessToken = lichessToken
    }

    // MARK: - Pasted / uploaded PGN

    /// Splits a pasted or uploaded (possibly multi-game) PGN blob into individual
    /// game PGN strings. A thin, explicit entry point over `MultiPGN.splitPGN` so
    /// callers have one client type for every import route.
    public func importPastedPGN(_ text: String) -> [String] {
        MultiPGN.splitPGN(text)
    }

    // MARK: - Account-linked import

    /// Fetches `username`'s public game history from `platform` and returns each
    /// game as an individually-importable PGN string. A username with zero public
    /// games returns an empty array (not an error) -- only a nonexistent username
    /// or a network/server failure throws.
    public func importAccount(platform: Platform, username: String) async throws -> [String] {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameImportError.userNotFound }
        switch platform {
        case .chessCom:
            return try await importFromChessCom(username: name)
        case .lichess:
            return try await importFromLichess(username: name)
        }
    }

    /// Convenience over `MultiPGN.detectSelfHandle` for an imported batch: passes
    /// the fetched username as the `prefer` hint so the uploader's own handle wins
    /// when it's among the games' common players.
    public static func detectSelfHandle(games: [String], username: String) -> String? {
        MultiPGN.detectSelfHandle(games: games, prefer: [username])
    }

    // MARK: - Chess.com

    private struct ChessComArchives: Decodable { var archives: [String] }
    private struct ChessComGame: Decodable { var pgn: String? }
    private struct ChessComGamesResponse: Decodable { var games: [ChessComGame] }

    /// `GET .../pub/player/{username}/games/archives` for the list of monthly
    /// archive URLs, then `GET` each archive (most recent first, capped at
    /// `defaultMaxArchives`) for its `games[].pgn` array. Concatenated and handed
    /// to `MultiPGN.splitPGN`, same as the pasted-text path.
    private func importFromChessCom(username: String) async throws -> [String] {
        let archivesURL = "\(chessComBaseURL)/pub/player/\(username.lowercased())/games/archives"
        let archivesData = try await get(archivesURL)
        guard let archives = try? JSONDecoder().decode(ChessComArchives.self, from: archivesData),
              !archives.archives.isEmpty
        else { return [] }

        let recent = archives.archives.suffix(Self.defaultMaxArchives)
        var pgns: [String] = []
        for archiveURL in recent {
            let gamesData = try await get(archiveURL)
            guard let response = try? JSONDecoder().decode(ChessComGamesResponse.self, from: gamesData) else {
                continue
            }
            for game in response.games {
                if let pgn = game.pgn, !pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pgns.append(pgn)
                }
            }
        }
        guard !pgns.isEmpty else { return [] }
        return MultiPGN.splitPGN(pgns.joined(separator: "\n\n"))
    }

    // MARK: - Lichess

    /// Delegates to the existing `LichessClient` (already does exactly this for one
    /// account) rather than re-implementing the request/parse logic here.
    private func importFromLichess(username: String) async throws -> [String] {
        let client = LichessClient(session: session, baseURL: lichessBaseURL, token: lichessToken)
        do {
            let games = try await client.fetchUserGames(username: username, max: Self.defaultLichessMax)
            return games.map { $0.pgn }
        } catch let error as LichessError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: LichessError) -> GameImportError {
        switch error {
        case .notFound, .badID:
            return .userNotFound
        case .network(let detail):
            return .network(detail)
        case .http(let code, let body):
            return .http(code, body)
        case .unauthorized:
            return .network("unauthorized")
        case .rateLimit:
            return .network("rate limit hit, try again shortly")
        case .emptyResponse:
            return .network("empty response")
        }
    }

    // MARK: - Request

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw GameImportError.network("bad URL") }
        var request = URLRequest(url: url)
        request.setValue("gemma-chess", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GameImportError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 404:
            throw GameImportError.userNotFound
        case let code where code >= 400:
            throw GameImportError.http(code, String(decoding: data, as: UTF8.self))
        default:
            return data
        }
    }
}
