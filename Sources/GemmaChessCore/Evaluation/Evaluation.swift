//  Evaluation.swift
//  Evaluation math: centipawns -> win%, move classification, per-move accuracy,
//  and game-speed (time-format) bucketing.
//
//  Ported 1:1 from the source project's `server/core/evaluation.py`. Formulas
//  follow Lichess's published approach; everything here is pure and deterministic
//  so it is trivially testable and reproducible.

import Foundation

/// Move quality label, by the drop in the mover's win%.
public enum Classification: String, Sendable, Equatable {
    case best, good, inaccuracy, mistake, blunder
}

/// Lichess-style time-format bucket for a game.
public enum Speed: String, Sendable, Equatable, CaseIterable {
    case bullet, blitz, rapid, classical, correspondence, unknown
}

/// (inaccuracy, mistake, blunder) win%-drop cutoffs, on the 0–100 scale.
public typealias Thresholds = (inaccuracy: Double, mistake: Double, blunder: Double)

public enum Evaluation {

    // MARK: Constants (mirror the source exactly)

    /// Lichess sigmoid constant for cp -> win%.
    static let winK = 0.003_682_08

    /// Clamp cp magnitude before the sigmoid; beyond this win% is already ~saturated.
    static let cpClamp = 1000.0

    /// Classification thresholds on the win% drop, in win% points (0–100 scale).
    /// Mirror Lichess's 0.1/0.2/0.3 on [-1,1] (×50 → 5/10/15).
    public static let blunderDrop = 15.0
    public static let mistakeDrop = 10.0
    public static let inaccuracyDrop = 5.0

    /// A move within this win% of the engine's best is considered "best".
    public static let bestEps = 2.0

    public static let defaultThresholds: Thresholds = (inaccuracyDrop, mistakeDrop, blunderDrop)

    /// Per-mode multiplier applied on top of the Elo-scaled cutoffs. Blitz is the
    /// anchor (1.0); slower modes are more sensitive, faster modes more forgiving.
    public static let speedThresholdFactors: [Speed: Double] = [
        .bullet: 1.15,
        .blitz: 1.0,
        .rapid: 0.9,
        .classical: 0.8,
        .correspondence: 0.75,
        .unknown: 1.0,
    ]

    // MARK: cp -> win%

    /// Convert a centipawn score (side-to-move relative) to a win% in [0, 100].
    /// cp == 0 -> 50. Positive favours the side to move.
    public static func winPercent(_ cp: Double) -> Double {
        let c = max(-cpClamp, min(cpClamp, cp))
        return 50.0 + 50.0 * (2.0 / (1.0 + exp(-winK * c)) - 1.0)
    }

    /// Win% from either a centipawn value or a mate-in-N. Exactly one is expected
    /// to be meaningful. Mate for the side to move -> ~100, mate against -> ~0.
    public static func winPercentFromScore(cp: Int?, mate: Int?) -> Double {
        if let mate {
            return mate > 0 ? 100.0 : 0.0
        }
        guard let cp else { return 50.0 }
        return winPercent(Double(cp))
    }

    // MARK: classification

    /// Classify a move by the drop in the mover's win% (winBefore - winAfter).
    /// Set `isBest` when the move played equals the engine's top choice.
    public static func classify(
        winBefore: Double,
        winAfter: Double,
        isBest: Bool = false,
        thresholds: Thresholds? = nil
    ) -> Classification {
        let (inacc, mist, blund) = thresholds ?? defaultThresholds
        // The engine's own top choice is always "best": you literally could not have
        // played better, so it must never be flagged a mistake/blunder. (Two separate
        // searches can report a few points of win% "drop" even for the best move; that
        // noise must not outrank the fact that it WAS the best move.)
        if isBest { return .best }
        let drop = winBefore - winAfter
        if drop >= blund { return .blunder }
        if drop >= mist { return .mistake }
        if drop >= inacc { return .inaccuracy }
        if drop <= bestEps { return .best }
        return .good
    }

    /// Scale the (inaccuracy, mistake, blunder) cutoffs to a player's skill.
    /// Stronger players make subtler errors, so their cutoffs shrink. `elo` is on a
    /// normalized scale; nil -> the default 5/10/15. Anchored so ~1500 -> ×1.0.
    public static func thresholdsForElo(_ elo: Double?) -> Thresholds {
        guard let elo else { return defaultThresholds }
        let factor = max(0.5, min(1.4, 1.75 - 0.0005 * elo))
        return (
            round1(defaultThresholds.inaccuracy * factor),
            round1(defaultThresholds.mistake * factor),
            round1(defaultThresholds.blunder * factor)
        )
    }

    /// Scale already-computed cutoffs by the game's mode (multiplies on top of
    /// `thresholdsForElo`). Blitz/unknown leave them unchanged.
    public static func thresholdsForSpeed(_ thresholds: Thresholds, speed: Speed?) -> Thresholds {
        let factor = speedThresholdFactors[speed ?? .unknown] ?? 1.0
        if factor == 1.0 { return thresholds }
        return (
            round1(thresholds.inaccuracy * factor),
            round1(thresholds.mistake * factor),
            round1(thresholds.blunder * factor)
        )
    }

    // MARK: accuracy

    /// Per-move accuracy% in [0, 100] from the win% drop (Lichess-style).
    public static func moveAccuracy(winBefore: Double, winAfter: Double) -> Double {
        let drop = max(0.0, winBefore - winAfter)
        let acc = 103.1668 * exp(-0.04354 * drop) - 3.1669
        return max(0.0, min(100.0, acc))
    }

    /// Aggregate per-move accuracies into a single per-side accuracy%.
    /// Empty -> 100 (no moves to fault).
    public static func aggregateAccuracy(_ accuracies: [Double]) -> Double {
        guard !accuracies.isEmpty else { return 100.0 }
        return accuracies.reduce(0, +) / Double(accuracies.count)
    }

    // MARK: game speed

    /// (base_seconds, increment_seconds) from a PGN TimeControl, or nil when it
    /// isn't a sudden-death clock ("-", "?", empty, or a correspondence "days" spec
    /// like "1/259200").
    public static func timeControlClock(_ timeControl: String?) -> (base: Double, increment: Double)? {
        let tc = (timeControl ?? "").trimmingCharacters(in: .whitespaces)
        if tc.isEmpty || tc == "-" || tc == "?" { return nil }
        let head: Substring
        let incPart: Substring?
        if let plus = tc.firstIndex(of: "+") {
            head = tc[tc.startIndex..<plus]
            incPart = tc[tc.index(after: plus)...]
        } else {
            head = Substring(tc)
            incPart = nil
        }
        if head.contains("/") { return nil }  // "1/259200" = correspondence (days)
        guard let base = Double(head) else { return nil }
        let increment: Double
        if let incPart, !incPart.isEmpty {
            guard let inc = Double(incPart) else { return nil }
            increment = inc
        } else {
            increment = 0.0
        }
        return base > 0 ? (base, increment) : nil
    }

    /// Bucket a game into bullet/blitz/rapid/classical/correspondence from its
    /// TimeControl, using the estimated duration base + 40*increment (Lichess's
    /// buckets). Falls back to an Event-header keyword, then "unknown".
    public static func classifySpeed(timeControl: String?, event: String? = nil) -> Speed {
        let tc = (timeControl ?? "").trimmingCharacters(in: .whitespaces)
        if !tc.isEmpty {
            let beforePlus = tc.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            if beforePlus.contains("/") { return .correspondence }
        }
        if let clock = timeControlClock(tc) {
            let estimated = clock.base + 40.0 * clock.increment
            if estimated < 180 { return .bullet }
            if estimated < 480 { return .blitz }
            if estimated < 1500 { return .rapid }
            return .classical
        }
        if tc == "-" { return .correspondence }  // lichess uses "-" for correspondence/unlimited
        let blob = (event ?? "").lowercased()
        for kw in [Speed.bullet, .blitz, .rapid, .classical, .correspondence] where blob.contains(kw.rawValue) {
            return kw
        }
        return .unknown
    }

    // MARK: helpers

    /// Round to 1 decimal place using round-half-to-even, matching Python's `round(x, 1)`.
    static func round1(_ x: Double) -> Double {
        (x * 10).rounded(.toNearestOrEven) / 10
    }
}
