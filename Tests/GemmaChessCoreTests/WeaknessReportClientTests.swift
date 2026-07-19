//  WeaknessReportClientTests.swift
//  Covers WeaknessReportClient (plan U4): the Pro-gate throws before any
//  network call, a successful response decodes the narrative, 402/403 map to
//  the same distinct errors ManagedCoach's /api/coach already does, and the
//  CoachingProfile -> WeaknessReportFacts mapping handles the empty-profile
//  case. Uses a mock URLProtocol, mirroring ManagedCoachTests exactly.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

/// A private mock, distinct from other suites' mock protocols per the lesson
/// already documented in ManagedCoachTests (shared global handlers race
/// across parallel suites).
final class WeaknessReportMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = WeaknessReportMockURLProtocol.handler else {
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

@Suite("WeaknessReportClient", .serialized)
struct WeaknessReportClientTests {

    static func makeClient(
        backendURL: String?, debugToken: String? = nil, appUserId: String? = "user-1",
        handler: @escaping (URLRequest) -> (Int, Data)
    ) -> WeaknessReportClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeaknessReportMockURLProtocol.self]
        WeaknessReportMockURLProtocol.handler = handler
        return WeaknessReportClient(
            session: URLSession(configuration: config),
            backendURL: { backendURL }, debugToken: { debugToken }, appUserId: { appUserId }
        )
    }

    private let facts = WeaknessReportFacts(
        topMotifs: [.init(motif: "missed_fork", count: 4)],
        weakestPhase: "endgame", recentAccuracy: 78, lifetimeAccuracy: 74, gamesAnalyzed: 12
    )

    @Test("not entitled (App Store channel) throws ProRequiredError before any network call")
    func gateFailureThrowsBeforeNetwork() async {
        defer { WeaknessReportMockURLProtocol.handler = nil }
        var networkCalled = false
        let client = Self.makeClient(backendURL: "https://gateway.test") { _ in
            networkCalled = true
            return (200, Data(#"{"text":"never reached"}"#.utf8))
        }
        await #expect(throws: ProRequiredError.self) {
            try await client.generateReport(facts: facts, channel: .appStore)
        }
        #expect(networkCalled == false)
    }

    @Test("local channel bypasses the gate and reaches the network (dev bypass preserved)")
    func localChannelBypassesGate() async throws {
        defer { WeaknessReportMockURLProtocol.handler = nil }
        var requestedURL: String?
        let client = Self.makeClient(backendURL: "https://gateway.test") { request in
            requestedURL = request.url?.absoluteString
            return (200, Data(#"{"text":"You tend to miss x-ray attacks."}"#.utf8))
        }
        let text = try await client.generateReport(facts: facts, channel: .local)

        #expect(text == "You tend to miss x-ray attacks.")
        #expect(requestedURL == "https://gateway.test/api/weaknessReport")
    }

    @Test("a 402 maps to a quota-specific error, distinct from 403")
    func quotaExceededMapsDistinctly() async {
        defer { WeaknessReportMockURLProtocol.handler = nil }
        let client = Self.makeClient(backendURL: "https://gateway.test") { _ in (402, Data()) }
        do {
            _ = try await client.generateReport(facts: facts, channel: .local)
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("limit"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("a 403 maps to a not-entitled error, distinct from quota")
    func notEntitledMapsDistinctly() async {
        defer { WeaknessReportMockURLProtocol.handler = nil }
        let client = Self.makeClient(backendURL: "https://gateway.test") { _ in (403, Data()) }
        do {
            _ = try await client.generateReport(facts: facts, channel: .local)
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("Pro"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("no backend configured throws without attempting a network call")
    func noBackendThrows() async {
        let client = WeaknessReportClient(backendURL: { nil }, debugToken: { nil }, appUserId: { "u" })
        await #expect(throws: CoachError.self) {
            try await client.generateReport(facts: facts, channel: .local)
        }
    }

    // MARK: - CoachingProfile -> WeaknessReportFacts mapping

    @Test("an empty profile (no games) maps to nil facts")
    func emptyProfileMapsToNil() {
        let profile = CoachingProfile(
            playerID: "me", displayName: "me", gamesAnalyzed: 0, generatedAt: "now",
            recent: nil, lifetime: nil, recentGames: []
        )
        #expect(CoachingProfileBuilder.weaknessReportFacts(profile) == nil)
    }

    @Test("a populated profile maps its recent view's motifs/phase/accuracy into facts")
    func populatedProfileMapsFacts() throws {
        let recent = CoachingProfile.View(
            window: 100, games: 12, avgAccuracy: 78,
            results: .init(win: 5, loss: 6, draw: 1),
            mistakeTotals: .init(inaccuracy: 3, mistake: 4, blunder: 2),
            mistakesPerGame: .init(inaccuracy: 0.25, mistake: 0.33, blunder: 0.17),
            topMotifs: [.init(motif: "missed_fork", count: 4), .init(motif: "back_rank", count: 2)],
            phaseLossTotal: .init(opening: 1, middlegame: 2, endgame: 5),
            weakestPhase: "endgame", bySpeed: [], openings: []
        )
        let lifetime = CoachingProfile.View(
            window: nil, games: 40, avgAccuracy: 74,
            results: .init(), mistakeTotals: .init(), mistakesPerGame: .init(),
            topMotifs: [], phaseLossTotal: .init(), weakestPhase: nil, bySpeed: [], openings: []
        )
        let profile = CoachingProfile(
            playerID: "me", displayName: "me", gamesAnalyzed: 40, generatedAt: "now",
            recent: recent, lifetime: lifetime, recentGames: []
        )

        let facts = try #require(CoachingProfileBuilder.weaknessReportFacts(profile))
        #expect(facts.topMotifs.map(\.motif) == ["missed_fork", "back_rank"])
        #expect(facts.topMotifs.first?.count == 4)
        #expect(facts.weakestPhase == "endgame")
        #expect(facts.recentAccuracy == 78)
        #expect(facts.lifetimeAccuracy == 74)
        #expect(facts.gamesAnalyzed == 40)
    }
}
