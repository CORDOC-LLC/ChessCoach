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

    /// Reference-typed box so the model choice can change between two calls
    /// without capturing a `var` in a `@Sendable` closure.
    final class ModelBox: @unchecked Sendable {
        var slug = "gemini-2.5-flash-lite"
    }

    @Test("GeminiCoach reads the model via a live closure, not a snapshot at init")
    func coachReadsModelDynamically() async throws {
        defer { GeminiMockURLProtocol.handler = nil }
        let box = ModelBox()
        let requested = RequestedURLs()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GeminiMockURLProtocol.self]
        GeminiMockURLProtocol.handler = { request in
            requested.append(request.url?.absoluteString ?? "")
            return (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.utf8))
        }
        let coach = GeminiCoach(
            session: URLSession(configuration: config), baseURL: "https://gemini.test",
            model: { box.slug }, apiKey: { "k" }
        )
        _ = try await coach.generate(system: "s", prompt: "p", sessionID: nil)
        box.slug = "gemini-2.5-pro"
        _ = try await coach.generate(system: "s", prompt: "p", sessionID: nil)

        #expect(requested.urls[0].contains("gemini-2.5-flash-lite"))
        #expect(requested.urls[1].contains("gemini-2.5-pro"))
    }
}

/// Thread-safe append-only log for the URLs the mock protocol observed.
final class RequestedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [String] = []
    var urls: [String] { lock.withLock { _urls } }
    func append(_ url: String) { lock.withLock { _urls.append(url) } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}

/// Pure Keychain/UserDefaults round-trips — no network mock, so this suite is
/// safe to run concurrently with anything (unlike GeminiCoachTests above, which
/// owns the shared GeminiMockURLProtocol.handler).
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

    @Test("model defaults to Flash and round-trips through UserDefaults")
    func modelRoundTrip() {
        let original = GeminiKeyStore.loadModel()
        defer { GeminiKeyStore.saveModel(original) }   // leave state clean for other tests

        GeminiKeyStore.saveModel(GeminiModelOption.flashLite.slug)
        #expect(GeminiKeyStore.loadModel() == "gemini-2.5-flash-lite")

        GeminiKeyStore.saveModel(GeminiModelOption.pro.slug)
        #expect(GeminiKeyStore.loadModel() == "gemini-2.5-pro")
    }
}
