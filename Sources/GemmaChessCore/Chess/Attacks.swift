//  Attacks.swift
//  Static attack/defense geometry over a ChessKit `Position`, plus the small board
//  queries the motif heuristics need (captures, en passant, legal-move enumeration,
//  forks, mate-in-1, back-rank weakness).
//
//  `chesskit-swift` does not publicly expose its bitboard attack maps, so we derive
//  attackers/defenders ourselves: for every piece of a colour we compute the squares
//  it attacks (pawns capture diagonally; knights/king by offset; sliders ray-cast and
//  stop at the first blocker, inclusive) and intersect that with the target square.
//  This mirrors python-chess's `board.attackers(color, sq)` / `board.attacks(sq)`
//  closely enough for the conservative, already-flagged-mistake motif tags.

import Foundation
import ChessKit

/// Pure, engine-free attack/defense and tactical-shape queries over a position.
enum BoardAttacks {

    /// Static piece values for the "is this piece hanging" / fork heuristics
    /// (king effectively infinite). Mirrors the source `_PIECE_VALUE`.
    static let pieceValue: [Piece.Kind: Int] = [
        .pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9, .king: 100,
    ]

    static func value(_ piece: Piece?) -> Int {
        guard let piece else { return 0 }
        return pieceValue[piece.kind] ?? 0
    }

    // MARK: Square geometry

    /// File index 0...7 (a...h).
    static func file(_ sq: Square) -> Int { sq.rawValue % 8 }
    /// Rank index 0...7 (rank 1 ... rank 8).
    static func rank(_ sq: Square) -> Int { sq.rawValue / 8 }

    static func square(file: Int, rank: Int) -> Square? {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return Square(rawValue: rank * 8 + file)
    }

    // MARK: Attack sets

    /// The squares attacked by `piece` in `position` (pawns: the two diagonal capture
    /// squares regardless of occupancy; sliders stop at — and include — the first
    /// blocker). Matches python-chess `board.attacks(square)`.
    static func attackSquares(of piece: Piece, in position: Position) -> [Square] {
        let f = file(piece.square)
        let r = rank(piece.square)
        var out: [Square] = []

        func add(_ file: Int, _ rank: Int) {
            if let sq = square(file: file, rank: rank) { out.append(sq) }
        }

        switch piece.kind {
        case .pawn:
            let dr = piece.color == .white ? 1 : -1
            add(f - 1, r + dr)
            add(f + 1, r + dr)
        case .knight:
            for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
                add(f + df, r + dr)
            }
        case .king:
            for df in -1...1 {
                for dr in -1...1 where !(df == 0 && dr == 0) {
                    add(f + df, r + dr)
                }
            }
        case .bishop:
            slide(f, r, [(1, 1), (1, -1), (-1, 1), (-1, -1)], in: position, into: &out)
        case .rook:
            slide(f, r, [(1, 0), (-1, 0), (0, 1), (0, -1)], in: position, into: &out)
        case .queen:
            slide(f, r, [(1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)],
                  in: position, into: &out)
        }
        return out
    }

    private static func slide(
        _ f: Int, _ r: Int, _ dirs: [(Int, Int)], in position: Position, into out: inout [Square]
    ) {
        for (df, dr) in dirs {
            var nf = f + df, nr = r + dr
            while let sq = square(file: nf, rank: nr) {
                out.append(sq)
                if position.piece(at: sq) != nil { break }  // blocker (inclusive)
                nf += df; nr += dr
            }
        }
    }

    /// Squares holding a piece of `color` that attack `square`. Matches python-chess
    /// `board.attackers(color, square)`.
    static func attackers(of color: Piece.Color, on square: Square, in position: Position) -> [Square] {
        var out: [Square] = []
        for piece in position.pieces where piece.color == color {
            if attackSquares(of: piece, in: position).contains(square) {
                out.append(piece.square)
            }
        }
        return out
    }

    // MARK: Move parsing / enumeration

    /// (from, to, promotion) of a UCI move string, or nil if malformed.
    static func parseUCI(_ uci: String) -> (from: Square, to: Square, promo: Piece.Kind?)? {
        guard uci.count >= 4 else { return nil }
        let chars = Array(uci)
        let from = Square(String(chars[0...1]))
        let to = Square(String(chars[2...3]))
        var promo: Piece.Kind?
        if chars.count >= 5 {
            switch Character(String(chars[4]).lowercased()) {
            case "q": promo = .queen
            case "r": promo = .rook
            case "b": promo = .bishop
            case "n": promo = .knight
            default: promo = nil
            }
        }
        return (from, to, promo)
    }

    /// Every legal move for the side to move in `fen`, as UCI strings (queen-promotes
    /// pawns reaching the last rank so the move applies cleanly).
    static func legalMovesUCI(fen: String) -> [String] {
        let dests = ChessLogic.legalDestinations(forFEN: fen)
        guard let position = Position(fen: fen) else { return [] }
        var out: [String] = []
        for (from, tos) in dests {
            let piece = position.piece(at: from)
            for to in tos {
                var uci = from.notation + to.notation
                if piece?.kind == .pawn {
                    let lastRank = piece?.color == .white ? 7 : 0
                    if rank(to) == lastRank { uci += "q" }
                }
                out.append(uci)
            }
        }
        return out
    }
}
