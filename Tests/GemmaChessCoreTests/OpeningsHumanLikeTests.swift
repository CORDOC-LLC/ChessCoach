//  OpeningsHumanLikeTests.swift
//  U1 — the Human-like opponent's book-continuation lookup: given SAN moves
//  played so far, a random next move from any vendored ECO line whose prefix
//  matches exactly, or nil once the game has left book.

import Testing
@testable import GemmaChessCore

@Suite("Openings: human-like book continuation")
struct OpeningsHumanLikeTests {

    @Test("empty history returns a move that is some real line's first move")
    func emptyHistoryReturnsARealFirstMove() throws {
        let move = Openings.bookContinuation(afterSAN: [])
        let picked = try #require(move)
        #expect(Openings.lines.contains { $0.sanMoves.first == picked })
    }

    @Test("a prefix matching multiple lines only ever returns a next move from a matching line")
    func matchingPrefixNeverReturnsAnUnrelatedMove() {
        // 1. e4 is a heavily represented prefix in the vendored ECO book.
        let prefix = ["e4"]
        for _ in 0..<50 {
            guard let move = Openings.bookContinuation(afterSAN: prefix) else { continue }
            let matches = Openings.lines.contains { line in
                line.sanMoves.count > prefix.count
                    && Array(line.sanMoves.prefix(prefix.count)) == prefix
                    && line.sanMoves[prefix.count] == move
            }
            #expect(matches)
        }
    }

    @Test("a prefix matching zero lines returns nil")
    func nonMatchingPrefixReturnsNil() {
        // An absurd, essentially-guaranteed-unmatched sequence of SAN tokens.
        let bogus = ["a4", "h5", "a5", "h4", "Ra3", "Rh6", "Ra2", "Rh7", "Ra1", "Rh8"]
        #expect(Openings.bookContinuation(afterSAN: bogus) == nil)
    }
}
