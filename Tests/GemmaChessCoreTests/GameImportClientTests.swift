//  GameImportClientTests.swift
//  U4 — PGN import: pasted text (real `MultiPGN.splitPGN`, no mocking needed) and
//  account-linked fetch from Chess.com/Lichess, driven by a mock `URLProtocol` (no
//  real network), mirroring `LichessTests.swift`'s existing convention.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

/// Routes requests by URL substring to a canned (status, body) response, so a single
/// test can serve both the Chess.com "archives" call and its follow-up "archive"
/// call with different bodies.
final class RoutingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = RoutingURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Always fails the request as if the network were unreachable -- for the
/// network-failure scenario, where no HTTP status is involved at all.
final class FailingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }
    override func stopLoading() {}
}

@Suite("GameImportClient", .serialized)
struct GameImportClientTests {

    static func makeClient(protocolClass: AnyClass) -> GameImportClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        return GameImportClient(
            session: URLSession(configuration: config),
            chessComBaseURL: "https://api.chess.test",
            lichessBaseURL: "https://lichess.test")
    }

    static let twoGamePGN = """
    [Event "Rated Blitz game"]
    [Site "https://lichess.test/aaaaaaaa"]
    [White "alice"]
    [Black "bob"]
    [Result "1-0"]
    [UTCDate "2026.01.02"]
    [WhiteElo "1500"]
    [BlackElo "1400"]
    [TimeControl "300+0"]

    1. e4 c5 2. Nf3 d6 1-0

    [Event "Rated Rapid game"]
    [Site "https://lichess.test/bbbbbbbb"]
    [White "alice"]
    [Black "carol"]
    [Result "0-1"]
    [UTCDate "2026.01.01"]
    [WhiteElo "1600"]
    [BlackElo "1550"]
    [TimeControl "600+5"]

    1. e4 e6 2. d4 d5 0-1
    """

    // MARK: 1. Pasted PGN (no mocking -- delegates to the real MultiPGN.splitPGN)

    @Test("pasted multi-game PGN splits into individual games via MultiPGN.splitPGN")
    func pastedPGNSplits() {
        let client = GameImportClient()
        let games = client.importPastedPGN(Self.twoGamePGN)
        #expect(games.count == 2)
        #expect(MultiPGN.headers(ofPGN: games[0])["White"] == "alice")
        #expect(MultiPGN.headers(ofPGN: games[1])["Black"] == "carol")
    }

    // MARK: 2. Chess.com account fetch

    @Test("valid Chess.com username with games fetches archives then games, split individually")
    func chessComAccountFetch() async throws {
        let archivesJSON = """
        {"archives": ["https://api.chess.test/pub/player/alice/games/2026/01"]}
        """
        let gamesJSON = """
        {"games": [
            {"pgn": "[Event \\"Live Chess\\"]\\n[White \\"alice\\"]\\n[Black \\"bob\\"]\\n[Result \\"1-0\\"]\\n\\n1. e4 e5 1-0\\n"},
            {"pgn": "[Event \\"Live Chess\\"]\\n[White \\"carol\\"]\\n[Black \\"alice\\"]\\n[Result \\"0-1\\"]\\n\\n1. d4 d5 0-1\\n"}
        ]}
        """
        RoutingURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if url.contains("/games/archives") { return (200, Data(archivesJSON.utf8)) }
            return (200, Data(gamesJSON.utf8))
        }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        let games = try await client.importAccount(platform: .chessCom, username: "alice")
        #expect(games.count == 2)
        #expect(MultiPGN.headers(ofPGN: games[0])["White"] == "alice")
        #expect(MultiPGN.headers(ofPGN: games[1])["Black"] == "alice")
    }

    // MARK: 3. Lichess account fetch

    @Test("valid Lichess username with games fetches PGN and splits individually")
    func lichessAccountFetch() async throws {
        RoutingURLProtocol.handler = { _ in (200, Data(Self.twoGamePGN.utf8)) }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        let games = try await client.importAccount(platform: .lichess, username: "alice")
        #expect(games.count == 2)
        #expect(MultiPGN.headers(ofPGN: games[0])["White"] == "alice")
    }

    // MARK: 4. Zero public games -> empty, not an error

    @Test("Chess.com username with zero public games returns an empty array, not an error")
    func chessComZeroGames() async throws {
        RoutingURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if url.contains("/games/archives") {
                return (200, Data(#"{"archives": []}"#.utf8))
            }
            return (200, Data(#"{"games": []}"#.utf8))
        }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        let games = try await client.importAccount(platform: .chessCom, username: "nobody-has-games")
        #expect(games.isEmpty)
    }

    @Test("Lichess username with zero public games returns an empty array, not an error")
    func lichessZeroGames() async throws {
        RoutingURLProtocol.handler = { _ in (200, Data()) }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        let games = try await client.importAccount(platform: .lichess, username: "nobody-has-games")
        #expect(games.isEmpty)
    }

    // MARK: 5. Invalid/nonexistent username -> distinct typed error

    @Test("a 404 from Chess.com maps to GameImportError.userNotFound")
    func chessComUserNotFound() async {
        RoutingURLProtocol.handler = { _ in (404, Data("not found".utf8)) }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        await #expect(throws: GameImportError.userNotFound) {
            _ = try await client.importAccount(platform: .chessCom, username: "no-such-user")
        }
    }

    @Test("a 404 from Lichess maps to GameImportError.userNotFound")
    func lichessUserNotFound() async {
        RoutingURLProtocol.handler = { _ in (404, Data("not found".utf8)) }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        await #expect(throws: GameImportError.userNotFound) {
            _ = try await client.importAccount(platform: .lichess, username: "no-such-user")
        }
    }

    // MARK: 6. Network failure -> distinct typed error, no crash

    @Test("a network failure during Chess.com fetch surfaces as GameImportError.network")
    func chessComNetworkFailure() async {
        let client = Self.makeClient(protocolClass: FailingURLProtocol.self)
        await #expect(throws: (any Error).self) {
            _ = try await client.importAccount(platform: .chessCom, username: "alice")
        }
        do {
            _ = try await client.importAccount(platform: .chessCom, username: "alice")
            Issue.record("expected a thrown error")
        } catch let error as GameImportError {
            guard case .network = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
        } catch {
            Issue.record("expected GameImportError, got \(error)")
        }
    }

    @Test("a network failure during Lichess fetch surfaces as GameImportError.network, distinct from userNotFound")
    func lichessNetworkFailure() async {
        let client = Self.makeClient(protocolClass: FailingURLProtocol.self)
        do {
            _ = try await client.importAccount(platform: .lichess, username: "alice")
            Issue.record("expected a thrown error")
        } catch let error as GameImportError {
            guard case .network = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
            #expect(error != .userNotFound)
        } catch {
            Issue.record("expected GameImportError, got \(error)")
        }
    }

    // MARK: 7. Self-handle detection on an imported batch

    @Test("detectSelfHandle passes the fetched username as the prefer hint and identifies the uploader")
    func selfHandleDetection() async throws {
        RoutingURLProtocol.handler = { _ in (200, Data(Self.twoGamePGN.utf8)) }
        defer { RoutingURLProtocol.handler = nil }

        let client = Self.makeClient(protocolClass: RoutingURLProtocol.self)
        let games = try await client.importAccount(platform: .lichess, username: "Alice")
        let handle = GameImportClient.detectSelfHandle(games: games, username: "Alice")
        // "alice" is white in both games (bob and carol are the two opponents), so
        // it's the unambiguous common handle regardless of the `prefer` hint's case.
        #expect(handle == "alice")
    }
}
