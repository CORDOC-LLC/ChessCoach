//  ManagedUsageClientTests.swift
//  Decodes chesscoach-gateway's /api/usage response shape and maps HTTP
//  errors to CoachError, driven by a mock URLProtocol (no real network).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

final class ManagedUsageMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = ManagedUsageMockURLProtocol.handler else {
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

@Suite("ManagedUsageClient", .serialized)
struct ManagedUsageClientTests {

    static func makeSession(handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManagedUsageMockURLProtocol.self]
        ManagedUsageMockURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    @Test("with no backend URL configured, throws without attempting a network call")
    func noBackendThrows() async {
        await #expect(throws: CoachError.self) {
            _ = try await ManagedUsageClient.fetchReport(
                since: .distantPast, until: .now,
                backendURL: { nil }, debugToken: { nil }, appUserId: { "user-1" }
            )
        }
    }

    @Test("decodes events and totals from the backend's JSON shape")
    func decodesHappyPath() async throws {
        defer { ManagedUsageMockURLProtocol.handler = nil }
        let body = """
        {
          "period": {"since": "2026-07-01T00:00:00.000Z", "until": "2026-07-08T00:00:00.000Z"},
          "events": [
            {"createdAt": "2026-07-08T10:00:00.573Z", "model": "google/gemini-2.5-flash-lite",
             "inputTokens": 100, "outputTokens": 20, "costUSD": 0.000018}
          ],
          "totals": {"inputTokens": 100, "outputTokens": 20, "costUSD": 0.000018}
        }
        """
        let session = Self.makeSession { _ in (200, Data(body.utf8)) }

        let report = try await ManagedUsageClient.fetchReport(
            since: Date(timeIntervalSince1970: 0), until: .now,
            session: session, backendURL: { "https://gateway.test" },
            debugToken: { "let-me-in" }, appUserId: { "user-1" }
        )

        #expect(report.events.count == 1)
        #expect(report.events[0].model == "google/gemini-2.5-flash-lite")
        #expect(report.events[0].inputTokens == 100)
        #expect(report.events[0].outputTokens == 20)
        #expect(abs(report.events[0].costUSD - 0.000018) < 1e-9)
        #expect(report.totalInputTokens == 100)
        #expect(report.totalOutputTokens == 20)
    }

    @Test("an empty events list decodes to an empty report, not a crash")
    func emptyEventsDecodes() async throws {
        defer { ManagedUsageMockURLProtocol.handler = nil }
        let body = """
        {"period": {"since": "2026-07-01T00:00:00.000Z", "until": "2026-07-08T00:00:00.000Z"},
         "events": [], "totals": {"inputTokens": 0, "outputTokens": 0, "costUSD": 0}}
        """
        let session = Self.makeSession { _ in (200, Data(body.utf8)) }

        let report = try await ManagedUsageClient.fetchReport(
            since: .distantPast, until: .now,
            session: session, backendURL: { "https://gateway.test" },
            debugToken: { nil }, appUserId: { "user-1" }
        )

        #expect(report.events.isEmpty)
        #expect(report.totalCostUSD == 0)
    }

    @Test("a non-2xx HTTP status maps to a CoachError naming the status code")
    func httpErrorMapsToCoachError() async {
        defer { ManagedUsageMockURLProtocol.handler = nil }
        let session = Self.makeSession { _ in (403, Data()) }

        do {
            _ = try await ManagedUsageClient.fetchReport(
                since: .distantPast, until: .now,
                session: session, backendURL: { "https://gateway.test" },
                debugToken: { nil }, appUserId: { "user-1" }
            )
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("403"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("the debug token is attached as X-Debug-Token when configured")
    func debugTokenAttached() async throws {
        defer { ManagedUsageMockURLProtocol.handler = nil }
        var capturedHeader: String?
        let session = Self.makeSession { request in
            capturedHeader = request.value(forHTTPHeaderField: "X-Debug-Token")
            return (200, Data(
                #"{"period":{"since":"2026-07-01T00:00:00.000Z","until":"2026-07-08T00:00:00.000Z"},"events":[],"totals":{"inputTokens":0,"outputTokens":0,"costUSD":0}}"#.utf8
            ))
        }

        _ = try await ManagedUsageClient.fetchReport(
            since: .distantPast, until: .now,
            session: session, backendURL: { "https://gateway.test" },
            debugToken: { "let-me-in" }, appUserId: { "user-1" }
        )

        #expect(capturedHeader == "let-me-in")
    }
}
