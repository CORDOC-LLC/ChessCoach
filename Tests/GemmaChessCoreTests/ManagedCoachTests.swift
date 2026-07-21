//  ManagedCoachTests.swift
//  The developer-hosted, metered coach backend, driven by a mock URLProtocol
//  (no real network, no real deployment). Covers: opt-in availability
//  (backend URL configured), a successful reply, the 402/403 status-code
//  mapping distinct from Gemini's, and the cumulative-text streaming
//  contract.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

/// A private mock, distinct from other suites' mock protocols — sharing one
/// global handler across suites racing in parallel causes cross-suite races
/// (a lesson already learned with GeminiCoachTests/LichessTests).
final class ManagedCoachMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = ManagedCoachMockURLProtocol.handler else {
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

/// A minimal Encodable facts payload -- these tests exercise `ManagedCoach`'s
/// HTTP/wire-format behavior directly, independent of any real `kind`'s facts shape.
private struct DummyFacts: Encodable {
    let note: String
}

@Suite("ManagedCoach", .serialized)
struct ManagedCoachTests {

    static func makeCoach(
        backendURL: String?, debugToken: String? = nil, appUserId: String? = "user-1",
        debugModel: String? = nil,
        handler: @escaping (URLRequest) -> (Int, Data)
    ) -> ManagedCoach {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManagedCoachMockURLProtocol.self]
        ManagedCoachMockURLProtocol.handler = handler
        return ManagedCoach(
            session: URLSession(configuration: config),
            backendURL: { backendURL },
            debugToken: { debugToken },
            appUserId: { appUserId },
            debugModel: { debugModel }
        )
    }

    @Test("no backend URL configured reports unavailable")
    func noBackendURLIsUnavailable() {
        let coach = ManagedCoach(backendURL: { nil }, debugToken: { nil }, appUserId: { nil })
        guard case .unavailable = coach.availability else {
            Issue.record("expected .unavailable with no backend URL"); return
        }
    }

    @Test("a configured backend URL reports available as .managed")
    func configuredURLIsAvailable() {
        let coach = ManagedCoach(backendURL: { "https://gateway.test" }, debugToken: { nil }, appUserId: { "u" })
        #expect(coach.availability == .managed)
    }

    @Test("generate() posts to /coach and parses the text response")
    func generateHappyPath() async throws {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        var requestedURL: String?
        var requestedMethod: String?
        let coach = Self.makeCoach(backendURL: "https://gateway.test") { request in
            requestedURL = request.url?.absoluteString
            requestedMethod = request.httpMethod
            return (200, Data(#"{"text":"Solid move.","usage":{"inputTokens":10,"outputTokens":5}}"#.utf8))
        }
        let reply = try await coach.generate(kind: .chat, facts: DummyFacts(note: "why?"), sessionID: nil)

        #expect(reply.answer == "Solid move.")
        #expect(requestedURL == "https://gateway.test/api/coach")
        #expect(requestedMethod == "POST")
    }

    @Test("the debug token is attached as X-Debug-Token when configured")
    func debugTokenHeaderAttached() async throws {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        var capturedHeader: String?
        let coach = Self.makeCoach(backendURL: "https://gateway.test", debugToken: "let-me-in") { request in
            capturedHeader = request.value(forHTTPHeaderField: "X-Debug-Token")
            return (200, Data(#"{"text":"ok","usage":{}}"#.utf8))
        }
        _ = try await coach.generate(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil)

        #expect(capturedHeader == "let-me-in")
    }

    @Test("effectiveModel: with a debug token AND a debug model, the model is sent")
    func effectiveModelWithToken() {
        #expect(ManagedCoach.effectiveModel(debugToken: "let-me-in", debugModel: "anthropic/claude-haiku-4.5")
                 == "anthropic/claude-haiku-4.5")
    }

    @Test("effectiveModel: WITHOUT a debug token, the model is never sent (KTD-3)")
    func effectiveModelWithoutToken() {
        #expect(ManagedCoach.effectiveModel(debugToken: nil, debugModel: "anthropic/claude-haiku-4.5") == nil)
        #expect(ManagedCoach.effectiveModel(debugToken: "", debugModel: "anthropic/claude-haiku-4.5") == nil)
    }

    @Test("effectiveModel: a token with no chosen model (\"server default\") sends nil")
    func effectiveModelServerDefault() {
        #expect(ManagedCoach.effectiveModel(debugToken: "let-me-in", debugModel: nil) == nil)
        #expect(ManagedCoach.effectiveModel(debugToken: "let-me-in", debugModel: "") == nil)
    }

    @Test("generate() succeeds end-to-end with both a debug token and a debug model configured")
    func generateWithDebugModelConfigured() async throws {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        let coach = Self.makeCoach(
            backendURL: "https://gateway.test", debugToken: "let-me-in", debugModel: "anthropic/claude-haiku-4.5"
        ) { _ in (200, Data(#"{"text":"Solid move.","model":"anthropic/claude-haiku-4.5","usage":{}}"#.utf8)) }

        let reply = try await coach.generate(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil)

        #expect(reply.answer == "Solid move.")
    }

    @Test("no backend configured throws without attempting a network call")
    func noBackendThrows() async {
        let coach = ManagedCoach(backendURL: { nil }, debugToken: { nil }, appUserId: { "u" })
        await #expect(throws: CoachError.self) {
            try await coach.generate(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil)
        }
    }

    @Test("a 402 maps to a quota-specific error, distinct from 403")
    func quotaExceededMapsDistinctly() async {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        let coach = Self.makeCoach(backendURL: "https://gateway.test") { _ in (402, Data()) }
        do {
            _ = try await coach.generate(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil)
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("limit"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("a 403 maps to a not-subscribed error, distinct from quota")
    func notSubscribedMapsDistinctly() async {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        let coach = Self.makeCoach(backendURL: "https://gateway.test") { _ in (403, Data()) }
        do {
            _ = try await coach.generate(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil)
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("Pro"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("stream() yields the server's cumulative text as-is, stopping at [DONE]")
    func streamingYieldsCumulativeText() async throws {
        defer { ManagedCoachMockURLProtocol.handler = nil }
        let sse = """
        data: {"text":"Solid "}

        data: {"text":"Solid move."}

        data: [DONE]

        """
        let coach = Self.makeCoach(backendURL: "https://gateway.test") { _ in (200, Data(sse.utf8)) }

        var chunks: [String] = []
        for try await partial in coach.stream(kind: .chat, facts: DummyFacts(note: "p"), sessionID: nil) {
            chunks.append(partial)
        }

        #expect(chunks == ["Solid ", "Solid move."])
    }
}
