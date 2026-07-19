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

    // MARK: Bundled packs

    /// The full bundled catalog (every bundled theme's `PuzzleThemeInfo`,
    /// including `minRating`) parsed once, lazily, from `Bundle.module`
    /// (mirrors `Openings.book`'s lazy-static loading style). `nil` if the
    /// bundled catalog is missing/corrupt -- exposed (not just the derived
    /// `bundledThemes` set) so tests can verify rating-band grouping against
    /// the real bundled data without duplicating the JSON.
    static let bundledCatalog: PuzzleCatalog? = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "puzzles"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(PuzzleCatalog.self, from: data)
    }()

    /// Theme ids bundled into this binary. Best-effort: a missing/corrupt
    /// bundled catalog just means no theme reports as bundled, degrading
    /// gracefully to the disk-cache/network path for everything.
    static let bundledThemes: Set<String> = Set(bundledCatalog?.themes.map(\.theme) ?? [])

    /// Whether `theme` ships inside the app binary (always available, never
    /// needs a download, and never deletable -- see `deletePack`).
    public static func isBundled(theme: String) -> Bool {
        bundledThemes.contains(theme)
    }

    /// Reads `theme`'s pack straight from the app bundle, or `nil` if it
    /// isn't one of the bundled themes.
    private static func bundledPack(theme: String) -> PuzzlePack? {
        guard let url = Bundle.module.url(forResource: theme, withExtension: "json", subdirectory: "puzzles"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(PuzzlePack.self, from: data)
    }

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

    /// `true` for a bundled theme even with an empty/nonexistent `baseDir` --
    /// bundled data is compiled into the binary, never cached to disk.
    public static func isDownloaded(theme: String, baseDir: URL = defaultBaseDir) -> Bool {
        if isBundled(theme: theme) { return true }
        return FileManager.default.fileExists(atPath: packPath(theme: theme, baseDir: baseDir).path)
    }

    public static func loadLocalPack(theme: String, baseDir: URL = defaultBaseDir) -> PuzzlePack? {
        if let bundled = bundledPack(theme: theme) { return bundled }
        guard let data = try? Data(contentsOf: packPath(theme: theme, baseDir: baseDir)) else { return nil }
        return try? JSONDecoder().decode(PuzzlePack.self, from: data)
    }

    /// Downloads `theme`'s pack and caches it to disk, or returns the cached
    /// copy if already downloaded (no re-fetch needed). Bundled themes are
    /// returned straight from the app binary -- no disk I/O, no network.
    public static func downloadPack(
        theme: String, session: URLSession = .shared, baseDir: URL = defaultBaseDir
    ) async throws -> PuzzlePack {
        if let bundled = bundledPack(theme: theme) { return bundled }
        if let cached = loadLocalPack(theme: theme, baseDir: baseDir) { return cached }
        let url = URL(string: "\(rawBaseURL)/packs/\(theme).json")!
        let (data, response) = try await session.data(from: url)
        try Self.checkOK(response)
        let pack = try JSONDecoder().decode(PuzzlePack.self, from: data)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try data.write(to: packPath(theme: theme, baseDir: baseDir), options: .atomic)
        return pack
    }

    /// Removes `theme`'s cached file from disk only -- a safe no-op if the
    /// theme is bundled (bundled data lives in the binary, not `baseDir`, so
    /// there's nothing to remove there) or if nothing was ever cached.
    public static func deletePack(theme: String, baseDir: URL = defaultBaseDir) {
        try? FileManager.default.removeItem(at: packPath(theme: theme, baseDir: baseDir))
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PuzzleError("Couldn't download puzzle data (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }
}
