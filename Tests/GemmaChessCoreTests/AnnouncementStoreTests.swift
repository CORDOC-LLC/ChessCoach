//  AnnouncementStoreTests.swift
//  Covers AnnouncementStore (pure show/dismiss/seen logic) and
//  AnnouncementClient's fail-soft network behavior (plan 2026-07-24-001, U2).

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("AnnouncementStore")
struct AnnouncementStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AnnouncementStoreTests-\(UUID().uuidString)")!
    }

    private func makeAnnouncement(
        id: String = "promo-1", expiresAt: Date? = nil
    ) -> Announcement {
        Announcement(id: id, title: "Title", body: "Body", link: "https://example.com", expiresAt: expiresAt)
    }

    @Test("shouldShow is true for an unexpired, undismissed announcement")
    func shouldShowTrueByDefault() {
        let a = makeAnnouncement()
        #expect(AnnouncementStore.shouldShow(a, dismissedIDs: []))
    }

    @Test("shouldShow is false once dismissed")
    func shouldShowFalseWhenDismissed() {
        let a = makeAnnouncement()
        #expect(!AnnouncementStore.shouldShow(a, dismissedIDs: [a.id]))
    }

    @Test("shouldShow is true when expiresAt is nil (never expires)")
    func shouldShowTrueWhenNoExpiry() {
        let a = makeAnnouncement(expiresAt: nil)
        #expect(AnnouncementStore.shouldShow(a, dismissedIDs: [], now: Date(timeIntervalSince1970: 10_000_000)))
    }

    @Test("shouldShow is false once expired")
    func shouldShowFalseWhenExpired() {
        let now = Date()
        let a = makeAnnouncement(expiresAt: now.addingTimeInterval(-60))
        #expect(!AnnouncementStore.shouldShow(a, dismissedIDs: [], now: now))
    }

    @Test("dismiss adds the id to dismissedIDs, and only that id")
    func dismissAddsID() {
        let defaults = freshDefaults()
        AnnouncementStore.dismiss(id: "promo-1", defaults: defaults)
        #expect(AnnouncementStore.dismissedIDs(defaults: defaults) == ["promo-1"])
        AnnouncementStore.dismiss(id: "promo-2", defaults: defaults)
        #expect(AnnouncementStore.dismissedIDs(defaults: defaults) == ["promo-1", "promo-2"])
    }

    @Test("recordSeen adds to the cache even for an announcement that would fail shouldShow")
    func recordSeenIndependentOfDismissState() {
        let defaults = freshDefaults()
        let a = makeAnnouncement(id: "dismissed-one")
        AnnouncementStore.dismiss(id: a.id, defaults: defaults)
        #expect(!AnnouncementStore.shouldShow(a, dismissedIDs: AnnouncementStore.dismissedIDs(defaults: defaults)))

        AnnouncementStore.recordSeen(a, defaults: defaults)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).contains(a))
    }

    @Test("recentlySeen cache caps at the limit, evicting oldest first")
    func cacheCapsAndEvictsOldest() {
        let defaults = freshDefaults()
        for i in 0..<(AnnouncementStore.recentlySeenCap + 1) {
            AnnouncementStore.recordSeen(makeAnnouncement(id: "promo-\(i)"), defaults: defaults)
        }
        let seen = AnnouncementStore.recentlySeen(defaults: defaults)
        #expect(seen.count == AnnouncementStore.recentlySeenCap)
        // Newest first: the very first recorded ("promo-0") should have been evicted.
        #expect(!seen.contains { $0.id == "promo-0" })
        #expect(seen.first?.id == "promo-\(AnnouncementStore.recentlySeenCap)")
    }

    @Test("reset clears both dismissed IDs and the recently-seen cache")
    func resetClearsEverything() {
        let defaults = freshDefaults()
        AnnouncementStore.dismiss(id: "promo-1", defaults: defaults)
        AnnouncementStore.recordSeen(makeAnnouncement(), defaults: defaults)
        AnnouncementStore.reset(defaults: defaults)
        #expect(AnnouncementStore.dismissedIDs(defaults: defaults).isEmpty)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).isEmpty)
    }

    @Test("dismissedIDs/recentlySeen decode as empty from corrupt or missing data, never crash")
    func corruptDataDecodesEmpty() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "announcements.dismissedIDs")
        defaults.set(Data("not json".utf8), forKey: "announcements.recentlySeen")
        #expect(AnnouncementStore.dismissedIDs(defaults: defaults).isEmpty)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).isEmpty)
    }
}

@Suite("AnnouncementClient")
struct AnnouncementClientTests {
    private func mockSession(host: String, status: Int, body: Data) -> URLSession {
        MockAnnouncementURLProtocol.register(host: host) { _ in (status, body) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAnnouncementURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("fetchCurrent returns the decoded announcement on a valid 200 response")
    func fetchCurrentSuccess() async {
        let host = "mock-announcement-\(UUID().uuidString).test"
        let json = Data("""
        {"id":"promo-1","title":"50% off","body":"For a limited time","link":"https://example.com"}
        """.utf8)
        let session = mockSession(host: host, status: 200, body: json)
        let result = await AnnouncementClient.fetchCurrent(backendURL: { "https://\(host)" }, session: session)
        #expect(result?.id == "promo-1")
        #expect(result?.title == "50% off")
    }

    @Test("fetchCurrent returns nil on a malformed response body")
    func fetchCurrentMalformedBody() async {
        let host = "mock-announcement-\(UUID().uuidString).test"
        let session = mockSession(host: host, status: 200, body: Data("not json".utf8))
        let result = await AnnouncementClient.fetchCurrent(backendURL: { "https://\(host)" }, session: session)
        #expect(result == nil)
    }

    @Test("fetchCurrent returns nil on a non-2xx response")
    func fetchCurrentNon2xx() async {
        let host = "mock-announcement-\(UUID().uuidString).test"
        let session = mockSession(host: host, status: 500, body: Data())
        let result = await AnnouncementClient.fetchCurrent(backendURL: { "https://\(host)" }, session: session)
        #expect(result == nil)
    }

    @Test("fetchCurrent returns nil when no backend URL is configured")
    func fetchCurrentNoBackend() async {
        let result = await AnnouncementClient.fetchCurrent(backendURL: { nil }, session: .shared)
        #expect(result == nil)
    }
}

/// A dedicated mock `URLProtocol` for `AnnouncementClient` tests -- keyed by
/// host like `MockManagedCoachURLProtocol` (`TestSupport.swift`), kept
/// separate so this suite doesn't share registration state with coach tests.
final class MockAnnouncementURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: (URLRequest) -> (Int, Data)] = [:]

    static func register(host: String, handler: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock(); handlers[host] = handler; lock.unlock()
    }

    private static func handler(for host: String) -> ((URLRequest) -> (Int, Data))? {
        lock.lock(); defer { lock.unlock() }
        return handlers[host]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return handler(for: host) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.handler(for: host) else {
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
