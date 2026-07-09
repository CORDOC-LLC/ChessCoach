//  PuzzleDownloadStore.swift
//  Downloads puzzle packs on demand from the public ChessCoach repo (plain
//  HTTPS, no entitlement, no backend) and caches them to disk so a theme only
//  needs to be fetched once. See PuzzleData/README.md for why this lives on
//  GitHub rather than chesscoach-gateway: puzzles are free, so they don't
//  belong on the same infrastructure as the metered coach.

import Foundation

/// Raised with a user-facing message when a puzzle pack can't be fetched.
public struct PuzzleError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum PuzzleDownloadStore {
    /// Tracks this branch until PuzzleData/ merges to main -- update here (one
    /// place) when it does, or switch to a versioned release-asset URL.
    private static let rawBaseURL =
        "https://raw.githubusercontent.com/CORDOC-LLC/ChessCoach/feat/gemmachess-core/PuzzleData"

    public static var defaultBaseDir: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GemmaChess/puzzles", isDirectory: true)
    }

    // MARK: Catalog

    /// Fetches the live catalog, caching it for offline listing afterward.
    public static func fetchCatalog(
        session: URLSession = .shared, baseDir: URL = defaultBaseDir
    ) async throws -> PuzzleCatalog {
        let url = URL(string: "\(rawBaseURL)/catalog.json")!
        let (data, response) = try await session.data(from: url)
        try Self.checkOK(response)
        let catalog = try JSONDecoder().decode(PuzzleCatalog.self, from: data)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? data.write(to: catalogCachePath(baseDir: baseDir), options: .atomic)
        return catalog
    }

    /// The last successfully-fetched catalog, if any -- lets the themes list
    /// render offline (already-downloaded packs still work with no network).
    public static func loadCachedCatalog(baseDir: URL = defaultBaseDir) -> PuzzleCatalog? {
        guard let data = try? Data(contentsOf: catalogCachePath(baseDir: baseDir)) else { return nil }
        return try? JSONDecoder().decode(PuzzleCatalog.self, from: data)
    }

    private static func catalogCachePath(baseDir: URL) -> URL {
        baseDir.appendingPathComponent("catalog.json")
    }

    // MARK: Packs

    private static func packPath(theme: String, baseDir: URL) -> URL {
        baseDir.appendingPathComponent("\(theme).json")
    }

    public static func isDownloaded(theme: String, baseDir: URL = defaultBaseDir) -> Bool {
        FileManager.default.fileExists(atPath: packPath(theme: theme, baseDir: baseDir).path)
    }

    public static func loadLocalPack(theme: String, baseDir: URL = defaultBaseDir) -> PuzzlePack? {
        guard let data = try? Data(contentsOf: packPath(theme: theme, baseDir: baseDir)) else { return nil }
        return try? JSONDecoder().decode(PuzzlePack.self, from: data)
    }

    /// Downloads `theme`'s pack and caches it to disk, or returns the cached
    /// copy if already downloaded (no re-fetch needed).
    public static func downloadPack(
        theme: String, session: URLSession = .shared, baseDir: URL = defaultBaseDir
    ) async throws -> PuzzlePack {
        if let cached = loadLocalPack(theme: theme, baseDir: baseDir) { return cached }
        let url = URL(string: "\(rawBaseURL)/packs/\(theme).json")!
        let (data, response) = try await session.data(from: url)
        try Self.checkOK(response)
        let pack = try JSONDecoder().decode(PuzzlePack.self, from: data)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try data.write(to: packPath(theme: theme, baseDir: baseDir), options: .atomic)
        return pack
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PuzzleError("Couldn't download puzzle data (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }
}
