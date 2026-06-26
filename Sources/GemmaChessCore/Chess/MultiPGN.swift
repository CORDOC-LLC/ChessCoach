//  MultiPGN.swift
//  Split a multi-game PGN into individual games and figure out which player is "you".
//
//  Chess.com / Lichess let you export many games as a single PGN file (games
//  concatenated, each starting with an `[Event ...]` header). The analysis path
//  takes one game at a time, so the paste/upload flow uses this to fan a file out
//  into per-game PGNs and to detect the uploader's handle (the one appearing in
//  every game).
//
//  Ported 1:1 from the source `server/core/multipgn.py`. Splitting is text-based
//  and lossless (original headers + `[%clk]` comments preserved); ChessKit is used
//  only to validate that a chunk actually contains a game.

import Foundation
import ChessKit

/// Multi-game PGN splitting, header reading, and uploader-handle detection.
public enum MultiPGN {

    /// Split immediately before each line that starts a new game's tag-pair
    /// section. Mirrors the source `_EVENT_BOUNDARY` regex `(?m)^(?=\[Event\b)`.
    private static let eventBoundary = try! NSRegularExpression(pattern: "(?m)^\\[Event\\b")

    /// Split a (possibly multi-game) PGN into individual game PGN strings, in file
    /// order.
    ///
    /// Lossless: each returned string is the original text for that game
    /// (clocks/headers intact). Chunks that don't parse into a game with at least
    /// one move are dropped, so a stray header block or trailing whitespace never
    /// becomes a bogus game.
    public static func splitPGN(_ text: String) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var games: [String] = []
        for chunk in segments(of: text) {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // Validate: a chunk must parse and contain at least one move.
            guard let game = try? Game(pgn: trimmed), !game.moves.isEmpty else { continue }
            games.append(trimmed + "\n")
        }
        return games
    }

    /// The tag-pair headers of a single game PGN (empty dict if unreadable).
    public static func headers(ofPGN pgn: String) -> [String: String] {
        guard let game = try? Game(pgn: pgn) else { return [:] }
        var result: [String: String] = [:]
        for tag in game.tags.all where !tag.wrappedValue.isEmpty {
            result[tag.name] = tag.wrappedValue
        }
        for (key, value) in game.tags.other where !value.isEmpty {
            result[key] = value
        }
        return result
    }

    /// The handle that appears (as White or Black) in *every* game — i.e. the
    /// uploader.
    ///
    /// In a personal export you are in all of your games, so the intersection of
    /// the players across games is (usually) just you. Returns the original-case
    /// handle. If a `prefer` handle (e.g. a configured username / aliases) is among
    /// the common set, it wins; otherwise a single unambiguous common handle is
    /// returned, else `nil` (caller falls back to per-game auto-detect).
    public static func detectSelfHandle(games: [String], prefer: [String] = []) -> String? {
        guard !games.isEmpty else { return nil }

        // Per game: lowercased handle -> original case.
        var perGame: [[String: String]] = []
        for game in games {
            let h = headers(ofPGN: game)
            var names: [String: String] = [:]
            for key in ["White", "Black"] {
                let raw = (h[key] ?? "").trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { names[raw.lowercased()] = raw }
            }
            perGame.append(names)
        }

        var common: Set<String>?
        for names in perGame {
            let keys = Set(names.keys)
            common = common.map { $0.intersection(keys) } ?? keys
        }
        let commonSet = common ?? []
        if commonSet.isEmpty { return nil }

        func originalCase(_ lowercased: String) -> String {
            for names in perGame {
                if let original = names[lowercased] { return original }
            }
            return lowercased
        }

        let preferLowercased = Set(
            prefer
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
        for candidate in commonSet where preferLowercased.contains(candidate) {
            return originalCase(candidate)
        }
        if commonSet.count == 1 {
            return originalCase(commonSet.first!)
        }
        return nil  // ambiguous (e.g. every game vs the same opponent)
    }

    // MARK: Private

    /// Slice `text` at every `[Event` line boundary, returning the raw substrings
    /// (including any text before the first boundary). Empty/whitespace segments
    /// are filtered by the caller.
    private static func segments(of text: String) -> [String] {
        let ns = text as NSString
        let matches = eventBoundary.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [text] }

        let starts = matches.map { $0.range.location }
        var result: [String] = []
        // Any prefix before the first [Event boundary.
        if let first = starts.first, first > 0 {
            result.append(ns.substring(to: first))
        }
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : ns.length
            result.append(ns.substring(with: NSRange(location: start, length: end - start)))
        }
        return result
    }
}
