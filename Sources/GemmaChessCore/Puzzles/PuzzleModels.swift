//  PuzzleModels.swift
//  Wire format for the curated Lichess puzzle packs (see PuzzleData/README.md
//  at the repo root for provenance, license (CC0), and curation method).
//  Puzzles are a free feature: no entitlement, no token cost, just static
//  JSON downloaded on demand and cached to disk.

import Foundation

/// One puzzle. `moves` is Lichess's own convention: UCI moves alternating
/// starting with the "setup" move (played automatically to reach the position
/// the solver actually sees), then the solver's move, then the opponent's
/// forced reply, and so on. Only the solver's moves (odd indices) are ever
/// typed in by the user; the rest play automatically.
public struct Puzzle: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fen: String
    public var moves: [String]
    public var rating: Int
    public var themes: [String]
}

/// One theme's downloaded pack.
public struct PuzzlePack: Codable, Sendable, Equatable {
    public var theme: String
    public var puzzles: [Puzzle]
}

/// One theme's catalog entry — enough to show a row before anything is
/// downloaded (count, rating range, and how big the download is).
public struct PuzzleThemeInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { theme }
    public var theme: String
    public var count: Int
    public var minRating: Int?
    public var maxRating: Int?
    public var file: String
    public var sizeKB: Double

    /// A human label for the raw Lichess theme id ("backRankMate" -> "Back-Rank Mate").
    public var displayName: String { Self.displayName(for: theme) }

    /// Same lookup, usable from just a theme id string (e.g. `PuzzleViewModel.
    /// activeTheme`) without needing a full `PuzzleThemeInfo`.
    public static func displayName(for theme: String) -> String {
        displayNames[theme] ?? theme
    }

    private static let displayNames: [String: String] = [
        "fork": "Forks",
        "pin": "Pins",
        "skewer": "Skewers",
        "discoveredAttack": "Discovered Attacks",
        "doubleCheck": "Double Checks",
        "backRankMate": "Back-Rank Mates",
        "smotheredMate": "Smothered Mates",
        "hangingPiece": "Hanging Pieces",
        "trappedPiece": "Trapped Pieces",
        "sacrifice": "Sacrifices",
        "deflection": "Deflection",
        "attraction": "Attraction",
        "clearance": "Clearance",
        "xRayAttack": "X-Ray Attacks",
        "zugzwang": "Zugzwang",
        "mateIn1": "Mate in 1",
        "mateIn2": "Mate in 2",
        "mateIn3": "Mate in 3",
        "endgame": "Endgames",
        "opening": "Openings",
    ]
}

public struct PuzzleCatalog: Codable, Sendable, Equatable {
    public var themes: [PuzzleThemeInfo]
}
