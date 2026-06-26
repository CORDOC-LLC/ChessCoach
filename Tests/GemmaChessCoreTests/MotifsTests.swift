//  MotifsTests.swift
//  U9 — engine-free motif tagging. Each case is a hand-built, unambiguous position
//  whose only point is the heuristic under test.

import Testing
@testable import GemmaChessCore

@Suite("Motifs")
struct MotifsTests {

    @Test("hung_piece: a queen moved en prise to an undefended square")
    func hungPiece() {
        // White Qd1 -> d5; d5 is attacked by the e6 pawn and defended by nobody.
        let motifs = Motifs.tagMotifs(
            fenBefore: "4k3/8/4p3/8/8/8/8/3QK3 w - - 0 1",
            moveUCI: "d1d5", bestUCI: nil, winSwing: 40, evalBefore: 0)
        #expect(motifs.contains("hung_piece"))
    }

    @Test("missed_fork: the engine's best move was a royal knight fork we didn't play")
    func missedFork() {
        // Best is Nd5-b6 forking Ka8 and Qc8; we played the quiet h-pawn instead.
        let motifs = Motifs.tagMotifs(
            fenBefore: "k1q5/8/8/3N4/8/8/7P/4K3 w - - 0 1",
            moveUCI: "h2h3", bestUCI: "d5b6", winSwing: 30, evalBefore: 0)
        #expect(motifs.contains("missed_fork"))
    }

    @Test("allowed_fork: our queen move let Black play a knight fork")
    func allowedFork() {
        // After Qd1-d4, Black has Ng5-f3+ forking Kg1 and Qd4.
        let motifs = Motifs.tagMotifs(
            fenBefore: "6k1/8/8/6n1/8/8/8/3Q2K1 w - - 0 1",
            moveUCI: "d1d4", bestUCI: nil, winSwing: 35, evalBefore: 0)
        #expect(motifs.contains("allowed_fork"))
    }

    @Test("back_rank: a boxed-in king let Black mate on the back rank")
    func backRank() {
        // Pawns f2/g2/h2 give no luft; after the quiet Nh3-g5, Black's Rd8-d1 is mate.
        let motifs = Motifs.tagMotifs(
            fenBefore: "3r3k/8/8/8/8/7N/5PPP/6K1 w - - 0 1",
            moveUCI: "h3g5", bestUCI: nil, winSwing: 50, evalBefore: 0)
        #expect(motifs.contains("back_rank"))
    }

    @Test("time_trouble: low clock / far behind the opponent")
    func timeTrouble() {
        // Low absolute clock.
        #expect(Motifs.timeMotifs(clockAfter: 20, oppClock: 200, base: 300) == ["time_trouble"])
        // Far behind the opponent on a small fraction of the base.
        #expect(Motifs.timeMotifs(clockAfter: 40, oppClock: 200, base: 300) == ["time_trouble"])
        // Comfortable clock -> nothing.
        #expect(Motifs.timeMotifs(clockAfter: 200, oppClock: 210, base: 300).isEmpty)
        // No clock data -> nothing.
        #expect(Motifs.timeMotifs(clockAfter: nil, oppClock: nil, base: 300).isEmpty)
    }

    @Test("a quiet, sound opening move tags nothing")
    func quietMove() {
        let motifs = Motifs.tagMotifs(
            fenBefore: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moveUCI: "e2e4", bestUCI: nil, winSwing: 1, evalBefore: 20)
        #expect(motifs.isEmpty)
    }
}
