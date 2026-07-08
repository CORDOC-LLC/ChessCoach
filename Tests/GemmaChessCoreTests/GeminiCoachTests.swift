//  GeminiCoachTests.swift
//  The optional cloud coach backend, driven by a mock URLProtocol (no real
//  network, no real key). Covers: opt-in availability, a successful reply,
//  HTTP error mapping, and a safety-blocked response.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

/// A private mock, distinct from `LichessTests`' `MockURLProtocol` — sharing one
/// global handler across suites racing in parallel caused cross-suite failures.
final class GeminiMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = GeminiMockURLProtocol.handler else {
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

@Suite("GeminiCoach", .serialized)
struct GeminiCoachTests {

    static func makeCoach(key: String?, handler: @escaping (URLRequest) -> (Int, Data)) -> GeminiCoach {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GeminiMockURLProtocol.self]
        GeminiMockURLProtocol.handler = handler
        return GeminiCoach(
            session: URLSession(configuration: config),
            baseURL: "https://gemini.test",
            apiKey: { key }
        )
    }

    @Test("no stored key reports unavailable, not a crash")
    func noKeyIsUnavailable() {
        let coach = GeminiCoach(apiKey: { nil })
        guard case .unavailable = coach.availability else {
            Issue.record("expected .unavailable with no key"); return
        }
    }

    @Test("a stored key reports available as .gemini")
    func keyIsAvailable() {
        let coach = GeminiCoach(apiKey: { "test-key" })
        #expect(coach.availability == .gemini)
    }

    @Test("generate() parses the first candidate's joined text")
    func generateParsesText() async throws {
        defer { GeminiMockURLProtocol.handler = nil }
        let body = """
        {"candidates":[{"content":{"parts":[{"text":"The knight "},{"text":"controls e5."}]}}]}
        """
        let coach = Self.makeCoach(key: "k") { _ in (200, Data(body.utf8)) }
        let reply = try await coach.generate(system: "sys", prompt: "why?", sessionID: nil)
        #expect(reply.answer == "The knight controls e5.")
    }

    @Test("no key raises a clear CoachError instead of hitting the network")
    func generateWithNoKeyThrows() async {
        let coach = GeminiCoach(apiKey: { nil })
        await #expect(throws: CoachError.self) {
            try await coach.generate(system: "sys", prompt: "p", sessionID: nil)
        }
    }

    @Test("a 401 maps to a friendly 'key was rejected' error")
    func unauthorizedMapsToFriendlyError() async {
        defer { GeminiMockURLProtocol.handler = nil }
        let coach = Self.makeCoach(key: "bad-key") { _ in (401, Data()) }
        await #expect(throws: CoachError.self) {
            try await coach.generate(system: "sys", prompt: "p", sessionID: nil)
        }
    }

    @Test("a safety block with no candidates raises an error naming the reason")
    func blockedResponseThrows() async {
        defer { GeminiMockURLProtocol.handler = nil }
        let body = """
        {"promptFeedback":{"blockReason":"SAFETY"}}
        """
        let coach = Self.makeCoach(key: "k") { _ in (200, Data(body.utf8)) }
        do {
            _ = try await coach.generate(system: "sys", prompt: "p", sessionID: nil)
            Issue.record("expected a throw")
        } catch let error as CoachError {
            #expect(error.message.contains("SAFETY"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

@Suite("GeminiKeyStore", .serialized)
struct GeminiKeyStoreTests {

    @Test("save then load round-trips; saving nil/empty clears it")
    func roundTrip() {
        GeminiKeyStore.save(nil)
        #expect(GeminiKeyStore.load() == nil)

        GeminiKeyStore.save("abc123")
        #expect(GeminiKeyStore.load() == "abc123")

        GeminiKeyStore.save("  ")   // whitespace-only counts as clearing
        #expect(GeminiKeyStore.load() == nil)

        GeminiKeyStore.save(nil)   // leave the real Keychain clean for other tests/runs
    }
}
