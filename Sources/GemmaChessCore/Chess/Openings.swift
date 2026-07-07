//  Openings.swift
//  Local ECO/opening-name lookup, so games whose PGN lacks Opening/ECO headers
//  still get named (e.g. Chess.com exports — Lichess ships the names, Chess.com
//  bulk exports often don't).
//
//  Engine-free and deterministic. We vendor the Lichess `chess-openings` dataset
//  (`Resources/eco/{a..e}.tsv`, ~3.7k named lines) and key it by placement + side +
//  castling rights (FEN's first three fields) so transpositions collapse to the
//  same position. The en-passant field is deliberately dropped, not just the move
//  counters: `ChessLogic.finalFEN(forPGN:)` (used to build the book) doesn't compute
//  it, while `ChessLogic.fen(afterMove:)` (used by live play) does — so keying on it
//  would silently miss every opening ending in a two-square pawn push (e4, d4, …:
//  most of them). Two positions differing only by ep-capture availability are the
//  same opening line anyway. Classification walks a game's positions in play order
//  and keeps the DEEPEST match — the most specific named line the game reached.
//
//  Ported 1:1 from the source `server/core/openings.py`.

import Foundation
import ChessKit

/// Opening classification by deepest position match against the vendored ECO data.
public enum Openings {

    /// EPD (position key) -> (eco, name). Built once, lazily, on first lookup.
    ///
    /// Replays each line's movetext to its final position; ~3.7k short lines, a
    /// one-time cost paid by the first classification, then reused for the process.
    /// Best-effort: a missing/corrupt data file contributes nothing (callers
    /// degrade to no name).
    static let book: [String: Opening] = loadBook()

    /// A classified opening: its ECO code and human-readable name.
    public struct Opening: Equatable, Sendable {
        public let eco: String
        public let name: String

        public init(eco: String, name: String) {
            self.eco = eco
            self.name = name
        }
    }

    /// Deepest opening match across a game's positions, or `nil`.
    ///
    /// `fens` are positions in play order — pass an analysis timeline's FENs
    /// straight in (no re-parse, no engine). Overwriting on every hit leaves the
    /// deepest match.
    public static func classifyFromFens(_ fens: [String]) -> Opening? {
        guard !book.isEmpty else { return nil }
        var best: Opening?
        for fen in fens {
            guard let key = positionKey(fromFEN: fen) else { continue }
            if let hit = book[key] { best = hit }
        }
        return best
    }

    /// Book hit for a single position, or `nil` when it isn't a named line. Used by
    /// Play mode to refine the opening name live, one ply at a time (the caller keeps
    /// the deepest hit, so `nil` for an out-of-book position never erases the name).
    public static func match(fen: String) -> Opening? {
        guard let key = positionKey(fromFEN: fen) else { return nil }
        return book[key]
    }

    /// Deepest opening match for a full PGN string (convenience for callers without
    /// a pre-built timeline). Replays the mainline and reuses the FEN path.
    public static func classifyFromPgn(_ pgn: String) -> Opening? {
        guard let fens = ChessLogic.fens(forPGN: pgn) else { return nil }
        return classifyFromFens(fens)
    }

    // MARK: Private

    /// Placement + side-to-move + castling rights — the first three FEN fields —
    /// deliberately excluding en passant and the move counters. See the file header
    /// for why en passant specifically must be dropped, not just normalized.
    private static func positionKey(fromFEN fen: String) -> String? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3 else { return nil }
        return fields[0..<3].joined(separator: " ")
    }

    private static func loadBook() -> [String: Opening] {
        var book: [String: Opening] = [:]
        for letter in ["a", "b", "c", "d", "e"] {
            guard let url = Bundle.module.url(forResource: letter, withExtension: "tsv", subdirectory: "eco"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                // Skip the header row and any malformed lines.
                guard columns.count == 3, columns[0] != "eco" else { continue }
                let eco = String(columns[0])
                let name = String(columns[1])
                let movetext = String(columns[2])

                guard let fen = ChessLogic.finalFEN(forPGN: movetext),
                      let key = positionKey(fromFEN: fen) else { continue }
                book[key] = Opening(eco: eco, name: name)
            }
        }
        return book
    }
}
