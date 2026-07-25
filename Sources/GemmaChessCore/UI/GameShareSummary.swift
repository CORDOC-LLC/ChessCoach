//  GameShareSummary.swift
//  Everything the end-of-game surfaces render, as one plain value type
//  (plan 2026-07-25-002, U1). Deliberately pure and view-free: `GameResultShareCard`
//  is rendered off the live view tree by `ShareCardRenderer`, so it must be
//  constructible from plain values, and every threshold here is testable without
//  the engine or a running game.
//
//  Two rules in here are load-bearing and easy to break later:
//
//  1. ACCURACY GOES THROUGH `Evaluation` + `HistoryStore.round1`, NEVER a local
//     reimplementation. The card must agree with the Review screen and history.
//     Note that sharing the computation is necessary but NOT sufficient -- the
//     inputs have to match too. `moveRecords` is appended inside an async
//     analysis task, so a resignation mid-analysis leaves this computing over
//     one fewer record than history eventually stores. Callers must therefore
//     rebuild the summary whenever `moveRecords` changes rather than caching it.
//
//  2. NOTHING IS INVENTED. `earnedHeadline` returns nil when the player earned
//     nothing this game, rather than manufacturing encouragement. A card that
//     praises a player for a game they lost badly reads as mockery.

import Foundation
import ChessKit

/// One finished game, reduced to what the in-app banner and the exported share
/// card both need.
public struct GameShareSummary: Equatable, Sendable {

    /// A move as an `Equatable`/`Sendable` pair. `ChessKit.Square` is an
    /// `Int`-backed enum, so this composes for free -- but a tuple property
    /// would not synthesize `Equatable`, hence the nominal type.
    public struct Move: Equatable, Sendable {
        public let from: Square
        public let to: Square
        public init(from: Square, to: Square) { self.from = from; self.to = to }

        /// Parses a UCI pair like "g1f3". Returns nil for anything malformed so
        /// a bad record degrades to "no highlight" rather than a wrong one.
        public init?(uci: String) {
            guard uci.count >= 4 else { return nil }
            let chars = Array(uci)
            let from = Square(String(chars[0...1]))
            let to = Square(String(chars[2...3]))
            self.init(from: from, to: to)
        }
    }

    /// The board shown as the card's hero, plus what to say about it.
    ///
    /// OUTCOME-AWARE BY DESIGN (R1). Showing the final position unconditionally
    /// would make the most prominent element of a beginner's card a picture of
    /// their own king in checkmate -- the artifact they are least likely to
    /// post. Wins and draws show the finish; losses show the best move the
    /// player actually found.
    public struct Hero: Equatable, Sendable {
        public let fen: String
        /// Non-nil only when the hero is NOT the final position, so the viewer
        /// is never left wondering which moment they are looking at.
        public let caption: String?
        public let lastMove: Move?
        /// Only ever set for a final-position hero -- a mating net drawn over a
        /// mid-game position would be nonsense.
        public let terminalExplanation: ChessLogic.TerminalExplanation?
    }

    /// Plain-language banding for the accuracy number. Beginners demonstrably
    /// do not know what a bare percentage means (Chess.com benchmarks theirs to
    /// a school grade for exactly this reason), so the number never ships alone.
    /// No label is a judgement about the player.
    public enum AccuracyBand: String, CaseIterable, Equatable, Sendable {
        case excellent, strong, solid, gettingThere, learning

        public static func forAccuracy(_ accuracy: Double) -> AccuracyBand {
            switch accuracy {
            case 90...: return .excellent
            case 80..<90: return .strong
            case 70..<80: return .solid
            case 60..<70: return .gettingThere
            default: return .learning
            }
        }

        public var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .strong: return "Strong"
            case .solid: return "Solid"
            case .gettingThere: return "Getting there"
            case .learning: return "Learning"
            }
        }
    }

    /// One bucket of the move-quality ladder. Carries `label` so the strip can
    /// be spoken as well as coloured -- colour alone conveys nothing to a
    /// VoiceOver or colour-blind user.
    public struct QualityCount: Equatable, Sendable {
        public let classification: String
        public let count: Int
        public let label: String
    }

    public let accuracy: Double
    public let band: AccuracyBand
    /// Positive-first, empty buckets omitted. Lichess's negative-only model
    /// (inaccuracy/mistake/blunder, no praise tier) is the wrong shape for a
    /// card meant to be shared.
    public let qualityCounts: [QualityCount]
    public let bestMoveCount: Int
    public let gradedMoveCount: Int
    public let hero: Hero
    public let orientation: BoardOrientation
    public let openingName: String?
    public let outcome: PlayOutcome
    public let resultHeadline: String
    public let stats: PlayStats
    /// What the player earned this game, or nil when the data supports nothing
    /// honest. Never a consolation prize.
    public let earnedHeadline: String?

    /// Whether any move was graded. Views gate accuracy display on this: a
    /// game that ended before analysis produced anything would otherwise
    /// render a meaningless 100%.
    public var hasGradedMoves: Bool { gradedMoveCount > 0 }

    /// Speakable equivalent of the coloured quality strip.
    public var qualityAccessibilityLabel: String {
        qualityCounts.map { "\($0.count) \($0.label.lowercased())" }.joined(separator: ", ")
    }

    public static let personalBestHeadline = "Your most accurate game yet"

    /// The ladder order, best-first. Unknown classification strings are ignored
    /// rather than bucketed, so a future engine label can't silently inflate a
    /// count.
    private static let ladder: [(key: String, label: String)] = [
        ("best", "Best"), ("good", "Good"),
        ("inaccuracy", "Inaccuracy"), ("mistake", "Mistake"), ("blunder", "Blunder"),
    ]

    public static func make(
        moveRecords: [CoachPromptBuilder.PlayMoveRecord],
        finalFEN: String,
        playerIsWhite: Bool,
        lastMove: Move?,
        terminalExplanation: ChessLogic.TerminalExplanation?,
        openingName: String?,
        outcome: PlayOutcome,
        isResignation: Bool,
        stats: PlayStats,
        priorAccuracies: [Double] = []
    ) -> GameShareSummary {
        // Same chain HistoryStore uses (HistoryStore.swift:362-365, 391) --
        // including its rounding, so R10 holds structurally rather than by
        // coincidence.
        let accuracies = moveRecords.map {
            Evaluation.moveAccuracy(winBefore: $0.winBefore, winAfter: $0.winAfter)
        }
        let accuracy = HistoryStore.round1(Evaluation.aggregateAccuracy(accuracies))

        var tally: [String: Int] = [:]
        for record in moveRecords { tally[record.classification, default: 0] += 1 }
        let counts = ladder.compactMap { entry -> QualityCount? in
            guard let n = tally[entry.key], n > 0 else { return nil }
            return QualityCount(classification: entry.key, count: n, label: entry.label)
        }
        let bestCount = tally[Classification.best.rawValue] ?? 0

        return GameShareSummary(
            accuracy: accuracy,
            band: .forAccuracy(accuracy),
            qualityCounts: counts,
            bestMoveCount: bestCount,
            gradedMoveCount: moveRecords.count,
            hero: hero(
                moveRecords: moveRecords, finalFEN: finalFEN, outcome: outcome,
                lastMove: lastMove, terminalExplanation: terminalExplanation),
            orientation: playerIsWhite ? .white : .black,
            openingName: openingName,
            outcome: outcome,
            resultHeadline: headline(
                outcome: outcome, isResignation: isResignation,
                terminalExplanation: terminalExplanation),
            stats: stats,
            earnedHeadline: earned(
                accuracy: accuracy, bestMoveCount: bestCount,
                gradedMoveCount: moveRecords.count, priorAccuracies: priorAccuracies)
        )
    }

    private static func hero(
        moveRecords: [CoachPromptBuilder.PlayMoveRecord],
        finalFEN: String,
        outcome: PlayOutcome,
        lastMove: Move?,
        terminalExplanation: ChessLogic.TerminalExplanation?
    ) -> Hero {
        let final = Hero(
            fen: finalFEN, caption: nil,
            lastMove: lastMove, terminalExplanation: terminalExplanation)
        guard outcome == .loss else { return final }

        // Prefer the player's best move -- but only if we actually stored the
        // position after it. `fen` is optional on records persisted before that
        // field existed, and a caption pointing at the wrong board is worse
        // than simply showing the finish.
        let best = moveRecords.last { $0.classification == Classification.best.rawValue }
        guard let best, let fen = best.fen, !fen.isEmpty else { return final }

        return Hero(
            fen: fen,
            caption: "Your best move: \(best.san)",
            lastMove: best.bestUCI.flatMap(Move.init(uci:)),
            terminalExplanation: nil
        )
    }

    /// Derived from the TYPED outcome, never by matching `resultText`'s English
    /// sentences -- that breaks the moment copy is edited or localized, and
    /// `resultText` is also restored from older persisted saves.
    private static func headline(
        outcome: PlayOutcome,
        isResignation: Bool,
        terminalExplanation: ChessLogic.TerminalExplanation?
    ) -> String {
        if isResignation { return "Resigned" }
        if let reason = terminalExplanation?.reason {
            switch reason {
            case .checkmate: return outcome == .win ? "Checkmate — you win" : "Checkmate"
            case .stalemate: return "Stalemate"
            }
        }
        switch outcome {
        case .win: return "You won"
        case .loss: return "Game over"
        case .draw: return "Draw"
        }
    }

    /// Priority order, stopping at the first honest claim: a genuine personal
    /// best, else what the player found this game, else nothing.
    private static func earned(
        accuracy: Double, bestMoveCount: Int, gradedMoveCount: Int, priorAccuracies: [Double]
    ) -> String? {
        guard gradedMoveCount > 0 else { return nil }
        // Three prior games is the floor for "yet" to mean anything.
        if priorAccuracies.count >= 3, let best = priorAccuracies.max(), accuracy > best {
            return personalBestHeadline
        }
        if bestMoveCount > 0 {
            let plural = bestMoveCount == 1 ? "time" : "times"
            return "You found the best move \(bestMoveCount) \(plural)"
        }
        return nil
    }
}
