//  GameShareSummaryTests.swift
//  Covers the pure summary behind the end-of-game card (plan 2026-07-25-002, U1).
//  Every threshold, the hero-selection rule, and the nil-vs-praise boundary are
//  pure functions, and these are the assertions that stop the card from lying.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("GameShareSummary")
struct GameShareSummaryTests {

    private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private static let midFEN = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

    private func record(
        _ classification: String, san: String = "e4",
        winBefore: Double = 50, winAfter: Double = 50,
        fen: String? = nil, bestUCI: String? = nil
    ) -> CoachPromptBuilder.PlayMoveRecord {
        CoachPromptBuilder.PlayMoveRecord(
            moveNumber: 1, san: san, classification: classification,
            winBefore: winBefore, winAfter: winAfter, betterSan: nil,
            bestUCI: bestUCI, fen: fen
        )
    }

    private func make(
        records: [CoachPromptBuilder.PlayMoveRecord],
        outcome: PlayOutcome = .loss,
        isResignation: Bool = false,
        priorAccuracies: [Double] = []
    ) -> GameShareSummary {
        GameShareSummary.make(
            moveRecords: records,
            finalFEN: Self.startFEN,
            playerIsWhite: true,
            lastMove: nil,
            terminalExplanation: nil,
            openingName: "Queen's Pawn Game",
            outcome: outcome,
            isResignation: isResignation,
            stats: PlayStats(wins: 0, losses: 7, draws: 0),
            priorAccuracies: priorAccuracies
        )
    }

    // MARK: Accuracy — the R10 anti-drift guard

    @Test("accuracy matches the Evaluation chain HistoryStore uses, composed by hand")
    func accuracyMatchesHistoryChain() {
        let pairs: [(Double, Double)] = [(50, 48), (60, 42), (55, 55), (70, 30)]
        let records = pairs.map { record("good", winBefore: $0.0, winAfter: $0.1) }
        let expected = HistoryStore.round1(
            Evaluation.aggregateAccuracy(
                pairs.map { Evaluation.moveAccuracy(winBefore: $0.0, winAfter: $0.1) }))

        #expect(make(records: records).accuracy == expected)
    }

    @Test("rounding matches HistoryStore's 1dp where 2dp would differ")
    func roundingMatchesOneDecimal() {
        let s = make(records: [record("good", winBefore: 50, winAfter: 43.7)])
        // Whatever the value, it must survive a round-trip through round1 unchanged.
        #expect(s.accuracy == HistoryStore.round1(s.accuracy))
    }

    // MARK: Empty / degenerate input

    @Test("no move records yields no accuracy claim and no earned headline")
    func emptyRecordsAreHonest() {
        let s = make(records: [])
        #expect(s.gradedMoveCount == 0)
        // `hasGradedMoves` is what the views gate on -- accuracy stays a plain
        // Double so callers can't accidentally render a meaningless 100%.
        #expect(s.hasGradedMoves == false)
        #expect(s.earnedHeadline == nil)
        #expect(s.qualityCounts.isEmpty)
    }

    // MARK: Bands

    @Test("bands run top to bottom without shaming wording")
    func bandsCoverTheRange() {
        #expect(GameShareSummary.AccuracyBand.forAccuracy(95) == .excellent)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(84) == .strong)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(72) == .solid)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(63) == .gettingThere)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(20) == .learning)
        // Boundaries are inclusive at the bottom of each band.
        #expect(GameShareSummary.AccuracyBand.forAccuracy(90) == .excellent)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(80) == .strong)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(70) == .solid)
        #expect(GameShareSummary.AccuracyBand.forAccuracy(60) == .gettingThere)
        // No band label is a judgement about the player.
        for band in GameShareSummary.AccuracyBand.allCases {
            #expect(!band.label.isEmpty)
        }
    }

    // MARK: Counts

    @Test("counts tally across a mixed set and survive an unknown classification")
    func countsTally() {
        let s = make(records: [
            record("best"), record("best"), record("good"),
            record("inaccuracy"), record("blunder"), record("wat"),
        ])
        #expect(s.bestMoveCount == 2)
        #expect(s.gradedMoveCount == 6)
        let dict = Dictionary(uniqueKeysWithValues: s.qualityCounts.map { ($0.classification, $0.count) })
        #expect(dict["best"] == 2)
        #expect(dict["good"] == 1)
        #expect(dict["inaccuracy"] == 1)
        #expect(dict["blunder"] == 1)
        // Unknown strings are ignored rather than crashing or inflating a bucket.
        #expect(dict["wat"] == nil)
    }

    @Test("quality counts are ordered positive-first and omit empty buckets")
    func countsArePositiveFirst() {
        let s = make(records: [record("blunder"), record("best"), record("good")])
        #expect(s.qualityCounts.map(\.classification) == ["best", "good", "blunder"])
    }

    @Test("every quality count carries speakable text, not colour alone")
    func countsAreAccessible() {
        let s = make(records: [record("best"), record("best"), record("inaccuracy")])
        #expect(s.qualityAccessibilityLabel.contains("2 best"))
        #expect(s.qualityAccessibilityLabel.contains("1 inaccuracy"))
    }

    // MARK: Earned headline — the R4 honesty boundary

    @Test("personal best fires only with 3+ prior games and a strict improvement")
    func personalBestRequiresHistoryAndImprovement() {
        let good = [record("best", winBefore: 50, winAfter: 50)]
        let s = make(records: good, priorAccuracies: [50, 60, 70])
        #expect(s.earnedHeadline == GameShareSummary.personalBestHeadline)
    }

    @Test("with prior games but no improvement, falls through to best-move count")
    func noImprovementFallsThrough() {
        let s = make(records: [record("best")], priorAccuracies: [100, 100, 100])
        #expect(s.earnedHeadline != GameShareSummary.personalBestHeadline)
        #expect(s.earnedHeadline?.contains("best move") == true)
    }

    @Test("fewer than 3 prior games never claims a personal best")
    func tooLittleHistoryNeverClaimsBest() {
        let s = make(records: [record("best")], priorAccuracies: [10, 20])
        #expect(s.earnedHeadline != GameShareSummary.personalBestHeadline)
    }

    @Test("best-move headline fires with no history at all")
    func bestMoveHeadlineNeedsNoHistory() {
        let s = make(records: [record("best"), record("best")])
        #expect(s.earnedHeadline?.contains("best move") == true)
    }

    @Test("zero best moves and no history returns nil rather than inventing praise")
    func nothingEarnedReturnsNil() {
        let s = make(records: [record("blunder"), record("mistake")])
        #expect(s.earnedHeadline == nil)
    }

    // MARK: Result headline — typed, never string-matched

    @Test("result headline derives from outcome, never from English result text")
    func headlineIsTyped() {
        #expect(make(records: [], outcome: .win).resultHeadline == "You won")
        #expect(make(records: [], outcome: .draw).resultHeadline == "Draw")
        #expect(make(records: [], outcome: .loss, isResignation: true).resultHeadline == "Resigned")
    }

    @Test("no headline carries an emoji")
    func headlineHasNoEmoji() {
        for outcome in [PlayOutcome.win, .loss, .draw] {
            let h = make(records: [], outcome: outcome).resultHeadline
            #expect(!h.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x238C })
        }
    }

    // MARK: Hero selection — the outcome-aware rule (R1)

    @Test("a win shows the final position")
    func winHeroIsFinalPosition() {
        let s = make(records: [record("best", fen: Self.midFEN)], outcome: .win)
        #expect(s.hero.fen == Self.startFEN)
        #expect(s.hero.caption == nil)
    }

    @Test("a draw shows the final position")
    func drawHeroIsFinalPosition() {
        let s = make(records: [record("best", fen: Self.midFEN)], outcome: .draw)
        #expect(s.hero.fen == Self.startFEN)
    }

    @Test("a loss shows the player's best move, not their own checkmate")
    func lossHeroIsBestMove() {
        let s = make(records: [
            record("blunder", san: "Qh5"),
            record("best", san: "Nf3", fen: Self.midFEN, bestUCI: "g1f3"),
        ], outcome: .loss)
        #expect(s.hero.fen == Self.midFEN)
        #expect(s.hero.caption?.contains("Nf3") == true)
        // The mating net belongs to the final position, not to a mid-game hero.
        #expect(s.hero.terminalExplanation == nil)
        #expect(s.hero.lastMove?.from == .g1)
        #expect(s.hero.lastMove?.to == .f3)
    }

    @Test("a loss with no best move falls back to the final position honestly")
    func lossWithoutBestMoveFallsBack() {
        let s = make(records: [record("blunder", san: "Qh5")], outcome: .loss)
        #expect(s.hero.fen == Self.startFEN)
        #expect(s.hero.caption == nil)
    }

    @Test("a loss whose best move has no stored FEN falls back rather than showing a wrong board")
    func lossBestMoveMissingFENFallsBack() {
        let s = make(records: [record("best", san: "Nf3", fen: nil)], outcome: .loss)
        #expect(s.hero.fen == Self.startFEN)
    }
}
