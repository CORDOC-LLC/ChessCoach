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
    static let book: [String: Opening] = loadAll().book

    /// Every vendored ECO line, in its raw move-sequence form -- the Opening
    /// Trainer's source of practiceable lines. Unlike `book` (keyed by final
    /// position, one entry per position -- later duplicates overwrite earlier
    /// ones), this keeps every named line's own move-by-move path so a line can
    /// be replayed and drilled ply by ply.
    public static let lines: [OpeningLine] = loadAll().lines

    /// A classified opening: its ECO code and human-readable name.
    public struct Opening: Equatable, Sendable {
        public let eco: String
        public let name: String

        public init(eco: String, name: String) {
            self.eco = eco
            self.name = name
        }
    }

    /// One named ECO line as an ordered sequence of SAN moves from the starting
    /// position -- what the Opening Trainer replays and quizzes against.
    public struct OpeningLine: Equatable, Sendable, Identifiable {
        public let eco: String
        public let name: String
        /// SAN moves in play order, e.g. `["e4", "c5", "Nf3", "d6"]`.
        public let sanMoves: [String]

        public init(eco: String, name: String, sanMoves: [String]) {
            self.eco = eco
            self.name = name
            self.sanMoves = sanMoves
        }

        /// Stable identity for persistence and list diffing: ECO lines can repeat
        /// (transpositions/sub-variations sharing a code), so the code alone
        /// isn't unique -- the full name plus move count disambiguates.
        public var id: String { "\(eco)|\(name)|\(sanMoves.count)" }
    }

    /// Case-insensitive substring search over both ECO code and name, e.g.
    /// `"sicilian"` or `"B20"`. Empty query returns every line.
    public static func search(_ query: String) -> [OpeningLine] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter {
            $0.name.range(of: trimmed, options: .caseInsensitive) != nil
                || $0.eco.range(of: trimmed, options: .caseInsensitive) != nil
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

    /// Parses every vendored TSV row once, building both the position-keyed
    /// `book` (for classification) and the ordered `lines` (for the trainer)
    /// from the same pass -- one file read, one movetext parse per row.
    private static func loadAll() -> (book: [String: Opening], lines: [OpeningLine]) {
        var book: [String: Opening] = [:]
        var lines: [OpeningLine] = []
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

                let sanMoves = sanMoves(fromMovetext: movetext)
                if !sanMoves.isEmpty {
                    lines.append(OpeningLine(eco: eco, name: name, sanMoves: sanMoves))
                }

                guard let fen = ChessLogic.finalFEN(forPGN: movetext),
                      let key = positionKey(fromFEN: fen) else { continue }
                book[key] = Opening(eco: eco, name: name)
            }
        }
        return (book, lines)
    }

    /// Strips move numbers (`"1."`, `"12..."`) from a movetext string, leaving
    /// just the SAN moves in play order. The vendored dataset is already plain
    /// SAN with no NAGs/comments/results, so whitespace-splitting plus a
    /// move-number filter is enough -- no need for a full PGN move-text parser.
    private static func sanMoves(fromMovetext movetext: String) -> [String] {
        movetext.split(separator: " ", omittingEmptySubsequences: true).compactMap { token in
            let isMoveNumber = token.allSatisfy { $0.isNumber || $0 == "." }
            return isMoveNumber ? nil : String(token)
        }
    }
}
