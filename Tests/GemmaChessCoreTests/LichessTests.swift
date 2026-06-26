//  LichessTests.swift
//  U11 — Lichess import driven by a mock URLProtocol (no real network).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

/// Intercepts every request on its session and replies from a thread-safe handler.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

@Suite("Lichess", .serialized)
struct LichessTests {

    static func makeClient() -> LichessClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return LichessClient(session: URLSession(configuration: config), baseURL: "https://lichess.test")
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
    [Opening "Sicilian Defense"]

    1. e4 c5 2. Nf3 d6 1-0

    [Event "Rated Rapid game"]
    [Site "https://lichess.test/bbbbbbbb"]
    [White "carol"]
    [Black "dave"]
    [Result "0-1"]
    [UTCDate "2026.01.01"]
    [WhiteElo "1600"]
    [BlackElo "1550"]
    [TimeControl "600+5"]
    [Opening "French Defense"]

    1. e4 e6 2. d4 d5 0-1
    """

    static let oneGamePGN = """
    [Event "Casual game"]
    [Site "https://lichess.test/aaaaaaaa"]
    [White "alice"]
    [Black "bob"]
    [Result "1-0"]
    [UTCDate "2026.01.02"]
    [TimeControl "300+0"]

    1. e4 c5 1-0
    """

    @Test("fetchUsergames parses a multi-game PGN into newest-first summaries")
    func userGames() async throws {
        MockURLProtocol.handler = { _ in (200, Data(Self.twoGamePGN.utf8)) }
        defer { MockURLProtocol.handler = nil }

        let games = try await Self.makeClient().fetchUserGames(username: "alice", max: 5)
        #expect(games.count == 2)

        let first = games[0]
        #expect(first.gameID == "aaaaaaaa")
        #expect(first.white == "alice")
        #expect(first.black == "bob")
        #expect(first.whiteElo == 1500)
        #expect(first.blackElo == 1400)
        #expect(first.result == "1-0")
        #expect(first.speed == "blitz")            // 300+0
        #expect(first.opening == "Sicilian Defense")
        #expect(first.date == "2026.01.02")

        #expect(games[1].gameID == "bbbbbbbb")
        #expect(games[1].speed == "rapid")          // 600+5
    }

    @Test("fetchGame accepts a bare id and a full URL with a color suffix")
    func singleGame() async throws {
        MockURLProtocol.handler = { _ in (200, Data(Self.oneGamePGN.utf8)) }
        defer { MockURLProtocol.handler = nil }
        let client = Self.makeClient()

        let byID = try await client.fetchGame(idOrURL: "aaaaaaaa")
        #expect(byID.gameID == "aaaaaaaa")
        #expect(byID.white == "alice")

        let byURL = try await client.fetchGame(idOrURL: "https://lichess.test/aaaaaaaa/white#12")
        #expect(byURL.gameID == "aaaaaaaa")
    }

    @Test("a 429 maps to LichessError.rateLimit")
    func rateLimited() async {
        MockURLProtocol.handler = { _ in (429, Data("slow down".utf8)) }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: LichessError.rateLimit) {
            _ = try await Self.makeClient().fetchUserGames(username: "alice")
        }
    }

    @Test("extractGameID strips URL noise and color suffixes")
    func extractID() {
        #expect(LichessClient.extractGameID("abcd1234") == "abcd1234")
        #expect(LichessClient.extractGameID("https://lichess.org/abcd1234/black") == "abcd1234")
        #expect(LichessClient.extractGameID("https://lichess.org/abcd1234ef/white#5") == "abcd1234")
    }
}
