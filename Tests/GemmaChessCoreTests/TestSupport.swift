//  TestSupport.swift
//  Shared test helpers.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GemmaChessCore

/// A mock `URLProtocol` for `ManagedCoach.mock(...)` (below), keyed by request
/// host rather than one shared global handler -- so tests across different
/// suites/files can each register their own handler under a unique host and
/// run concurrently without racing each other's responses (the same lesson
/// `ManagedCoachTests`'s own dedicated protocol class documents).
final class MockManagedCoachURLProtocol: URLProtocol, @unchecked Sendable {
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
        // `URLSession` moves a POST body from `httpBody` into `httpBodyStream`
        // before handing the request to a custom `URLProtocol` -- read it back
        // out and reattach it as `httpBody` so handlers can inspect the JSON
        // that was actually sent (mirrors what a real server would receive).
        var requestWithBody = request
        if requestWithBody.httpBody == nil, let stream = requestWithBody.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            stream.close()
            requestWithBody.httpBody = data
        }
        let (status, data) = handler(requestWithBody)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension ManagedCoach {
    /// A `ManagedCoach` wired to a unique mock host (never a real network
    /// call) -- `handler` receives the raw request and returns (status, body).
    /// Use this (rather than a fake `CoachLLM` conformer -- that protocol no
    /// longer exists, see `CoachLLM.swift`'s header) wherever a test needs a
    /// coach backend double; `CoachOrchestrator` now depends on `ManagedCoach`
    /// concretely.
    static func mock(
        appUserId: String? = "test-user",
        handler: @escaping (URLRequest) -> (Int, Data)
    ) -> ManagedCoach {
        let host = "mock-coach-\(UUID().uuidString).test"
        MockManagedCoachURLProtocol.register(host: host, handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockManagedCoachURLProtocol.self]
        return ManagedCoach(
            session: URLSession(configuration: config),
            backendURL: { "https://\(host)" },
            debugToken: { nil },
            appUserId: { appUserId },
            debugModel: { nil }
        )
    }

    /// A `ManagedCoach` that always answers `text` (200, `{"text": ...}`) --
    /// the common "just give me a working coach" case.
    static func mockAnswering(_ text: String, appUserId: String? = "test-user") -> ManagedCoach {
        mock(appUserId: appUserId) { _ in
            (200, Data("{\"text\":\"\(text)\"}".utf8))
        }
    }

    /// A `ManagedCoach` that always fails with `status` (e.g. 403 for a
    /// not-subscribed error, mapped by `ManagedCoach.checkStatus`).
    static func mockFailing(status: Int, appUserId: String? = "test-user") -> ManagedCoach {
        mock(appUserId: appUserId) { _ in (status, Data()) }
    }
}

@MainActor
extension PlayViewModel {
    /// A `PlayViewModel` wired to scratch, per-call persistence -- never the real
    /// Application Support directory or `UserDefaults.standard`. Every checkpoint
    /// now writes to disk (see `persistCheckpoint`), so plain `PlayViewModel()` in
    /// a test would race other parallel test suites over the same shared files.
    static func forTesting(coach: CoachOrchestrator = CoachOrchestrator()) -> PlayViewModel {
        let token = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayViewModelTests-\(token)", isDirectory: true)
        let historyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayViewModelHistoryTests-\(token)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "PlayViewModelTests-\(token)")!
        let statsDefaults = UserDefaults(suiteName: "PlayViewModelStatsTests-\(token)")!
        return PlayViewModel(
            coach: coach, savedGamesBaseDir: dir, savedGamesDefaults: defaults, statsDefaults: statsDefaults,
            historyBaseDir: historyDir)
    }
}

@MainActor
extension PuzzleViewModel {
    /// A `PuzzleViewModel` wired to scratch, per-call storage -- never the
    /// real Application Support directory or `UserDefaults.standard`.
    static func forTesting() -> PuzzleViewModel {
        let token = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PuzzleViewModelTests-\(token)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "PuzzleViewModelTests-\(token)")!
        return PuzzleViewModel(progressDefaults: defaults, puzzleBaseDir: dir)
    }
}
