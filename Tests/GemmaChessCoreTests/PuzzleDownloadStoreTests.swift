//  PuzzleDownloadStoreTests.swift
//  On-demand puzzle pack downloads: local cache round-trip (no network needed
//  once a pack exists on disk) and the mocked-network fetch path, using this
//  suite's own private mock URLProtocol (shared mocks race across suites --
//  a lesson already learned with ManagedCoachTests/GeminiCoachTests).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import GemmaChessCore

final class PuzzleDownloadMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = PuzzleDownloadMockURLProtocol.handler else {
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

@Suite("PuzzleDownloadStore", .serialized)
struct PuzzleDownloadStoreTests {

    private func tempBaseDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PuzzleDownloadStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func mockSession(handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PuzzleDownloadMockURLProtocol.self]
        PuzzleDownloadMockURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    // "quietMove" is deliberately not one of the 20 bundled themes (see
    // Resources/puzzles/catalog.json) -- these generic tests exercise the
    // disk-cache/network path, not the bundle-first path (see the "Bundle-
    // first lookup" tests below for that).
    private let samplePack = PuzzlePack(theme: "quietMove", puzzles: [
        Puzzle(id: "abc12", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2"], rating: 900, themes: ["quietMove"]),
    ])

    @Test("a pack already on disk is returned without touching the network")
    func returnsCachedPackWithoutNetworkCall() async throws {
        let dir = tempBaseDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(samplePack).write(to: dir.appendingPathComponent("quietMove.json"))

        var called = false
        let session = mockSession { _ in called = true; return (500, Data()) }

        let pack = try await PuzzleDownloadStore.downloadPack(theme: "quietMove", session: session, baseDir: dir)
        #expect(pack == samplePack)
        #expect(!called)
    }

    @Test("downloading a new pack fetches it and caches it to disk")
    func downloadsAndCaches() async throws {
        let dir = tempBaseDir()
        let data = try JSONEncoder().encode(samplePack)
        let session = mockSession { _ in (200, data) }

        let pack = try await PuzzleDownloadStore.downloadPack(theme: "quietMove", session: session, baseDir: dir)
        #expect(pack == samplePack)
        #expect(PuzzleDownloadStore.isDownloaded(theme: "quietMove", baseDir: dir))
        #expect(PuzzleDownloadStore.loadLocalPack(theme: "quietMove", baseDir: dir) == samplePack)
    }

    @Test("a non-2xx response throws instead of caching garbage")
    func failedDownloadThrows() async throws {
        let dir = tempBaseDir()
        let session = mockSession { _ in (404, Data()) }

        await #expect(throws: PuzzleError.self) {
            _ = try await PuzzleDownloadStore.downloadPack(theme: "quietMove", session: session, baseDir: dir)
        }
        #expect(!PuzzleDownloadStore.isDownloaded(theme: "quietMove", baseDir: dir))
    }

    @Test("fetchCatalog caches the catalog for offline listing")
    func fetchCatalogCaches() async throws {
        let dir = tempBaseDir()
        let catalog = PuzzleCatalog(themes: [
            PuzzleThemeInfo(theme: "fork", count: 1, minRating: 900, maxRating: 900, file: "fork.json", sizeKB: 0.1),
        ])
        let data = try JSONEncoder().encode(catalog)
        let session = mockSession { _ in (200, data) }

        let fetched = try await PuzzleDownloadStore.fetchCatalog(session: session, baseDir: dir)
        #expect(fetched == catalog)
        #expect(PuzzleDownloadStore.loadCachedCatalog(baseDir: dir) == catalog)
    }

    // MARK: Bundle-first lookup (U2)

    @Test("a bundled theme's pack loads with zero network calls and an empty baseDir")
    func bundledThemeLoadsWithoutNetwork() async throws {
        let dir = tempBaseDir() // never created -- proves baseDir isn't touched
        var called = false
        let session = mockSession { _ in called = true; return (500, Data()) }

        let pack = try await PuzzleDownloadStore.downloadPack(theme: "fork", session: session, baseDir: dir)
        #expect(pack.theme == "fork")
        #expect(!pack.puzzles.isEmpty)
        #expect(!called)
    }

    @Test("isBundled distinguishes bundled themes from downloadable-only ones")
    func isBundledDistinguishesThemes() {
        #expect(PuzzleDownloadStore.isBundled(theme: "fork"))
        #expect(!PuzzleDownloadStore.isBundled(theme: "quietMove"))
    }

    @Test("isDownloaded is true for a bundled theme even with an empty baseDir")
    func isDownloadedTrueForBundledTheme() {
        let dir = tempBaseDir() // never created
        #expect(PuzzleDownloadStore.isDownloaded(theme: "fork", baseDir: dir))
    }

    @Test("a non-bundled theme still follows the existing cache-then-network path")
    func nonBundledThemeUnchangedRegression() async throws {
        let dir = tempBaseDir()
        let data = try JSONEncoder().encode(samplePack)
        let session = mockSession { _ in (200, data) }

        let pack = try await PuzzleDownloadStore.downloadPack(theme: "quietMove", session: session, baseDir: dir)
        #expect(pack == samplePack)
        #expect(PuzzleDownloadStore.isDownloaded(theme: "quietMove", baseDir: dir))
        #expect(PuzzleDownloadStore.loadLocalPack(theme: "quietMove", baseDir: dir) == samplePack)
    }

    @Test("deletePack removes a cached theme's file, making isDownloaded false afterward")
    func deletePackRemovesCachedTheme() async throws {
        let dir = tempBaseDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(samplePack).write(to: dir.appendingPathComponent("quietMove.json"))
        #expect(PuzzleDownloadStore.isDownloaded(theme: "quietMove", baseDir: dir))

        PuzzleDownloadStore.deletePack(theme: "quietMove", baseDir: dir)

        #expect(!PuzzleDownloadStore.isDownloaded(theme: "quietMove", baseDir: dir))
    }

    @Test("deletePack on a bundled theme is a safe no-op -- the theme still works afterward")
    func deletePackOnBundledThemeIsNoOp() async throws {
        let dir = tempBaseDir()
        var called = false
        let session = mockSession { _ in called = true; return (500, Data()) }

        PuzzleDownloadStore.deletePack(theme: "fork", baseDir: dir)

        #expect(PuzzleDownloadStore.isDownloaded(theme: "fork", baseDir: dir))
        let pack = try await PuzzleDownloadStore.downloadPack(theme: "fork", session: session, baseDir: dir)
        #expect(pack.theme == "fork")
        #expect(!called)
    }
}
