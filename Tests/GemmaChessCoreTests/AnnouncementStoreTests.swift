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

    @Test("a freshly-seen announcement is unread")
    func unreadByDefault() {
        let a = makeAnnouncement()
        #expect(AnnouncementStore.isUnread(a, readIDs: []))
    }

    @Test("marking read makes it not unread, leaving others alone")
    func markReadAffectsOnlyThatID() {
        let defaults = freshDefaults()
        let a = makeAnnouncement(id: "promo-1")
        let b = makeAnnouncement(id: "promo-2")
        AnnouncementStore.markRead(id: a.id, defaults: defaults)

        let read = AnnouncementStore.readIDs(defaults: defaults)
        #expect(read == ["promo-1"])
        #expect(!AnnouncementStore.isUnread(a, readIDs: read))
        #expect(AnnouncementStore.isUnread(b, readIDs: read))
    }

    @Test("an announcement with no expiry stays unread indefinitely")
    func unreadWhenNoExpiry() {
        let a = makeAnnouncement(expiresAt: nil)
        #expect(AnnouncementStore.isUnread(a, readIDs: [], now: Date(timeIntervalSince1970: 10_000_000)))
    }

    @Test("an expired announcement does not count as unread, but is still listed")
    func expiredIsNotUnreadButStillCached() {
        let defaults = freshDefaults()
        let now = Date()
        let a = makeAnnouncement(expiresAt: now.addingTimeInterval(-60))
        #expect(!AnnouncementStore.isUnread(a, readIDs: [], now: now))

        AnnouncementStore.recordSeen(a, defaults: defaults)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).contains(a))
    }

    @Test("IDs written under the old dismissed-ID key read as already-read (carry-over)")
    func oldDismissedIDsCarryOverAsRead() throws {
        let defaults = freshDefaults()
        // Simulate a device that dismissed this announcement under the prior
        // shipped banner behavior -- same key, written directly.
        let legacy: Set<String> = ["already-handled"]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "announcements.dismissedIDs")

        let a = makeAnnouncement(id: "already-handled")
        let read = AnnouncementStore.readIDs(defaults: defaults)
        #expect(read.contains("already-handled"))
        #expect(!AnnouncementStore.isUnread(a, readIDs: read))
    }

    @Test("hasUnread reflects the cache, and clears once everything is read")
    func hasUnreadTracksTheCache() {
        let defaults = freshDefaults()
        #expect(!AnnouncementStore.hasUnread(defaults: defaults))

        let a = makeAnnouncement(id: "promo-1")
        AnnouncementStore.recordSeen(a, defaults: defaults)
        #expect(AnnouncementStore.hasUnread(defaults: defaults))

        AnnouncementStore.markRead(id: a.id, defaults: defaults)
        #expect(!AnnouncementStore.hasUnread(defaults: defaults))
    }

    @Test("an expired-but-unread announcement does not badge")
    func expiredDoesNotBadge() {
        let defaults = freshDefaults()
        let now = Date()
        AnnouncementStore.recordSeen(makeAnnouncement(id: "old", expiresAt: now.addingTimeInterval(-60)),
                                     defaults: defaults)
        #expect(!AnnouncementStore.hasUnread(now: now, defaults: defaults))
    }

    @Test("recordSeen adds to the cache even for an already-read announcement")
    func recordSeenIndependentOfReadState() {
        let defaults = freshDefaults()
        let a = makeAnnouncement(id: "read-one")
        AnnouncementStore.markRead(id: a.id, defaults: defaults)
        #expect(!AnnouncementStore.isUnread(a, readIDs: AnnouncementStore.readIDs(defaults: defaults)))

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

    @Test("reset clears both read IDs and the recently-seen cache")
    func resetClearsEverything() {
        let defaults = freshDefaults()
        AnnouncementStore.markRead(id: "promo-1", defaults: defaults)
        AnnouncementStore.recordSeen(makeAnnouncement(), defaults: defaults)
        AnnouncementStore.reset(defaults: defaults)
        #expect(AnnouncementStore.readIDs(defaults: defaults).isEmpty)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).isEmpty)
    }

    @Test("readIDs/recentlySeen decode as empty from corrupt or missing data, never crash")
    func corruptDataDecodesEmpty() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "announcements.dismissedIDs")
        defaults.set(Data("not json".utf8), forKey: "announcements.recentlySeen")
        #expect(AnnouncementStore.readIDs(defaults: defaults).isEmpty)
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).isEmpty)
        #expect(!AnnouncementStore.hasUnread(defaults: defaults))
    }

    // MARK: Mailbox row behavior (plan U3)
    //
    // The list's tap handler marks exactly one ID read and opens a link only
    // for live announcements. Asserted through the store rather than the view,
    // which is why `AnnouncementsView` takes an injectable `defaults:`.

    @Test("tapping a row marks only that announcement read")
    func tapMarksOnlyThatAnnouncement() {
        let defaults = freshDefaults()
        let a = makeAnnouncement(id: "promo-1")
        let b = makeAnnouncement(id: "promo-2")
        AnnouncementStore.recordSeen(a, defaults: defaults)
        AnnouncementStore.recordSeen(b, defaults: defaults)

        AnnouncementStore.markRead(id: a.id, defaults: defaults)

        let read = AnnouncementStore.readIDs(defaults: defaults)
        #expect(read == ["promo-1"])
        #expect(AnnouncementStore.hasUnread(defaults: defaults))  // b is still unread

        AnnouncementStore.markRead(id: b.id, defaults: defaults)
        #expect(!AnnouncementStore.hasUnread(defaults: defaults))
    }

    @Test("an expired announcement can still be marked read, though it never badged")
    func expiredStillMarkable() {
        let defaults = freshDefaults()
        let now = Date()
        let a = makeAnnouncement(id: "old", expiresAt: now.addingTimeInterval(-60))
        AnnouncementStore.recordSeen(a, defaults: defaults)
        #expect(!AnnouncementStore.hasUnread(now: now, defaults: defaults))

        AnnouncementStore.markRead(id: a.id, defaults: defaults)
        #expect(AnnouncementStore.readIDs(defaults: defaults).contains("old"))
        // Still listed -- read state never removes it from the mailbox (R7).
        #expect(AnnouncementStore.recentlySeen(defaults: defaults).contains(a))
    }

    @Test("a link-less announcement can be marked read (it would be inert otherwise)")
    func linklessStillMarkable() {
        let defaults = freshDefaults()
        let a = Announcement(id: "no-link", title: "T", body: "B", link: nil, expiresAt: nil)
        AnnouncementStore.recordSeen(a, defaults: defaults)
        #expect(AnnouncementStore.hasUnread(defaults: defaults))

        AnnouncementStore.markRead(id: a.id, defaults: defaults)
        #expect(!AnnouncementStore.hasUnread(defaults: defaults))
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
