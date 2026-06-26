//  CapturedMaterial.swift
//  A pure, engine-free helper that derives captured material from a FEN by diffing
//  the position's piece multiset against the standard starting army. Used by the
//  Play-mode captured tray (icons + net material delta). Side-effect-free and
//  trivially unit-testable.

import Foundation

/// Captured pieces for both sides plus the net material balance, derived from a FEN.
public struct CapturedMaterial: Equatable, Sendable {

    /// Black pieces that have been captured (i.e. captured *by* White), as FEN
    /// chars (lowercase), sorted by descending value.
    public var capturedByWhite: [Character]
    /// White pieces that have been captured (i.e. captured *by* Black), as FEN
    /// chars (uppercase), sorted by descending value.
    public var capturedByBlack: [Character]
    /// Signed material balance from White's perspective: positive = White is ahead.
    /// Uses standard values P1 N3 B3 R5 Q9.
    public var delta: Int

    public init(capturedByWhite: [Character], capturedByBlack: [Character], delta: Int) {
        self.capturedByWhite = capturedByWhite
        self.capturedByBlack = capturedByBlack
        self.delta = delta
    }

    /// Standard piece value (kings excluded).
    public static func value(of piece: Character) -> Int {
        switch Character(piece.lowercased()) {
        case "p": return 1
        case "n", "b": return 3
        case "r": return 5
        case "q": return 9
        default: return 0
        }
    }

    /// Capturable piece kinds per side at the start, with their counts.
    private static let startCounts: [Character: Int] =
        ["p": 8, "n": 2, "b": 2, "r": 2, "q": 1]

    /// Diff a FEN's placement against the standard start.
    ///
    /// Caveat (documented): a *promoted* pawn lowers the pawn count without being a
    /// capture, so a promotion reads as a "captured pawn" in this naïve diff. This is
    /// a minor, intentional display limitation — see plan U3.
    public static func from(fen: String) -> CapturedMaterial {
        let placement = BoardGeometry.placement(fromFEN: fen)
        var whiteOnBoard: [Character: Int] = [:]   // uppercase
        var blackOnBoard: [Character: Int] = [:]   // lowercase
        for piece in placement.values {
            if piece.isUppercase {
                whiteOnBoard[Character(piece.lowercased()), default: 0] += 1
            } else {
                blackOnBoard[piece, default: 0] += 1
            }
        }

        var capturedByWhite: [Character] = []   // black pieces gone
        var capturedByBlack: [Character] = []   // white pieces gone
        var whiteCapturedValue = 0
        var blackCapturedValue = 0

        for (kind, start) in startCounts {
            let missingBlack = max(0, start - (blackOnBoard[kind] ?? 0))
            let missingWhite = max(0, start - (whiteOnBoard[kind] ?? 0))
            let upper = Character(kind.uppercased())
            for _ in 0..<missingBlack {
                capturedByWhite.append(kind)
                whiteCapturedValue += value(of: kind)
            }
            for _ in 0..<missingWhite {
                capturedByBlack.append(upper)
                blackCapturedValue += value(of: kind)
            }
        }

        let byValueDesc: (Character, Character) -> Bool = { value(of: $0) > value(of: $1) }
        return CapturedMaterial(
            capturedByWhite: capturedByWhite.sorted(by: byValueDesc),
            capturedByBlack: capturedByBlack.sorted(by: byValueDesc),
            delta: whiteCapturedValue - blackCapturedValue
        )
    }
}
