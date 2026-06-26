//  EvaluationTests.swift
//  Covers U2 test scenarios from the implementation plan.

import Testing
@testable import GemmaChessCore

@Suite("Evaluation: cp -> win%")
struct WinPercentTests {

    @Test("cp == 0 is 50%")
    func zeroIsFifty() {
        #expect(abs(Evaluation.winPercent(0) - 50.0) < 1e-9)
    }

    @Test("large positive cp saturates near 100, negative near 0, symmetric")
    func saturation() {
        let hi = Evaluation.winPercent(2000)   // beyond clamp
        let lo = Evaluation.winPercent(-2000)
        #expect(hi > 95.0 && hi <= 100.0)
        #expect(lo < 5.0 && lo >= 0.0)
        #expect(abs((hi - 50.0) - (50.0 - lo)) < 1e-9)  // symmetric about 50
    }

    @Test("clamp: magnitudes beyond ±1000 give the same win% as ±1000")
    func clampBeyondLimit() {
        #expect(Evaluation.winPercent(1000) == Evaluation.winPercent(5000))
        #expect(Evaluation.winPercent(-1000) == Evaluation.winPercent(-9999))
    }

    @Test("monotonic increasing in cp")
    func monotonic() {
        #expect(Evaluation.winPercent(-100) < Evaluation.winPercent(0))
        #expect(Evaluation.winPercent(0) < Evaluation.winPercent(100))
        #expect(Evaluation.winPercent(100) < Evaluation.winPercent(300))
    }

    @Test("winPercentFromScore: mate and nil handling")
    func fromScore() {
        #expect(Evaluation.winPercentFromScore(cp: nil, mate: 3) == 100.0)
        #expect(Evaluation.winPercentFromScore(cp: nil, mate: -2) == 0.0)
        #expect(Evaluation.winPercentFromScore(cp: nil, mate: nil) == 50.0)
        #expect(abs(Evaluation.winPercentFromScore(cp: 0, mate: nil) - 50.0) < 1e-9)
    }
}

@Suite("Evaluation: classification")
struct ClassifyTests {

    @Test("drop boundaries map to the right label")
    func boundaries() {
        // before=100 keeps arithmetic simple: drop == 100 - after
        #expect(Evaluation.classify(winBefore: 100, winAfter: 85) == .blunder)   // drop 15
        #expect(Evaluation.classify(winBefore: 100, winAfter: 85.1) == .mistake) // drop 14.9
        #expect(Evaluation.classify(winBefore: 100, winAfter: 90) == .mistake)   // drop 10
        #expect(Evaluation.classify(winBefore: 100, winAfter: 90.1) == .inaccuracy) // drop 9.9
        #expect(Evaluation.classify(winBefore: 100, winAfter: 95) == .inaccuracy) // drop 5
        #expect(Evaluation.classify(winBefore: 100, winAfter: 95.1) == .good)    // drop 4.9, not best
    }

    @Test("best by isBest flag or tiny drop")
    func bestCases() {
        #expect(Evaluation.classify(winBefore: 100, winAfter: 80, isBest: true) == .blunder) // big drop wins over isBest
        #expect(Evaluation.classify(winBefore: 50, winAfter: 49, isBest: true) == .best)
        #expect(Evaluation.classify(winBefore: 50, winAfter: 48.5) == .best)   // drop 1.5 <= bestEps(2)
        #expect(Evaluation.classify(winBefore: 50, winAfter: 47.5) == .good)   // drop 2.5 > bestEps, < inacc
    }

    @Test("custom thresholds override defaults")
    func customThresholds() {
        let t: Thresholds = (2, 4, 6)
        #expect(Evaluation.classify(winBefore: 100, winAfter: 93, thresholds: t) == .blunder) // drop 7 >= 6
        #expect(Evaluation.classify(winBefore: 100, winAfter: 97, thresholds: t) == .inaccuracy) // drop 3 >= 2
    }
}

@Suite("Evaluation: threshold scaling")
struct ThresholdScalingTests {

    @Test("nil elo -> default 5/10/15")
    func elaNil() {
        let t = Evaluation.thresholdsForElo(nil)
        #expect(t == Evaluation.defaultThresholds)
    }

    @Test("~1500 elo -> ~x1.0")
    func elo1500() {
        // factor = 1.75 - 0.0005*1500 = 1.0
        let t = Evaluation.thresholdsForElo(1500)
        #expect(t.inaccuracy == 5.0 && t.mistake == 10.0 && t.blunder == 15.0)
    }

    @Test("elo factor clamps at 0.5 (very strong) and 1.4 (very weak)")
    func eloClamps() {
        let strong = Evaluation.thresholdsForElo(3000)  // 1.75 - 1.5 = 0.25 -> clamp 0.5
        #expect(strong.inaccuracy == 2.5 && strong.mistake == 5.0 && strong.blunder == 7.5)
        let weak = Evaluation.thresholdsForElo(0)        // 1.75 -> clamp 1.4
        #expect(weak.inaccuracy == 7.0 && weak.mistake == 14.0 && weak.blunder == 21.0)
    }

    @Test("speed factors: bullet more lenient, classical stricter, unknown unchanged")
    func speedFactors() {
        let base = Evaluation.defaultThresholds
        let bullet = Evaluation.thresholdsForSpeed(base, speed: .bullet)   // ×1.15
        // round-half-to-even (matches Python round): 5.75->5.8, 11.5->11.5, 17.25->17.2
        #expect(bullet.inaccuracy == 5.8 && bullet.mistake == 11.5 && bullet.blunder == 17.2)
        let classical = Evaluation.thresholdsForSpeed(base, speed: .classical) // ×0.8
        #expect(classical.inaccuracy == 4.0 && classical.mistake == 8.0 && classical.blunder == 12.0)
        #expect(Evaluation.thresholdsForSpeed(base, speed: .unknown) == base)
        #expect(Evaluation.thresholdsForSpeed(base, speed: nil) == base)
    }
}

@Suite("Evaluation: accuracy")
struct AccuracyTests {

    @Test("zero drop -> ~100% (formula peaks at 99.9999, capped at 100)")
    func zeroDrop() {
        let acc = Evaluation.moveAccuracy(winBefore: 50, winAfter: 50)
        #expect(abs(acc - 100.0) < 0.001 && acc <= 100.0)
    }

    @Test("accuracy decreases monotonically with drop and is clamped")
    func monotonicClamped() {
        let a = Evaluation.moveAccuracy(winBefore: 100, winAfter: 95)  // drop 5
        let b = Evaluation.moveAccuracy(winBefore: 100, winAfter: 80)  // drop 20
        let c = Evaluation.moveAccuracy(winBefore: 100, winAfter: 0)   // drop 100
        #expect(a > b && b > c)
        #expect(c >= 0.0 && a <= 100.0)
    }

    @Test("negative drop (improving) is treated as zero drop -> ~100%")
    func negativeDrop() {
        let acc = Evaluation.moveAccuracy(winBefore: 40, winAfter: 60)
        #expect(abs(acc - 100.0) < 0.001 && acc <= 100.0)
    }

    @Test("aggregate empty -> 100, else mean")
    func aggregate() {
        #expect(Evaluation.aggregateAccuracy([]) == 100.0)
        #expect(Evaluation.aggregateAccuracy([90, 100, 80]) == 90.0)
    }
}

@Suite("Evaluation: game speed")
struct SpeedTests {

    @Test("time control clock parsing")
    func clockParsing() {
        #expect(Evaluation.timeControlClock("300+5")! == (300, 5))
        #expect(Evaluation.timeControlClock("600")! == (600, 0))
        #expect(Evaluation.timeControlClock("-") == nil)
        #expect(Evaluation.timeControlClock("?") == nil)
        #expect(Evaluation.timeControlClock("") == nil)
        #expect(Evaluation.timeControlClock("1/259200") == nil)  // correspondence days
        #expect(Evaluation.timeControlClock("0+0") == nil)        // base must be > 0
    }

    @Test("speed buckets by estimated duration (base + 40*inc)")
    func buckets() {
        #expect(Evaluation.classifySpeed(timeControl: "60+0") == .bullet)     // 60
        #expect(Evaluation.classifySpeed(timeControl: "120+1") == .bullet)    // 120 + 40 = 160 < 180
        #expect(Evaluation.classifySpeed(timeControl: "180+0") == .blitz)     // 180
        #expect(Evaluation.classifySpeed(timeControl: "300+0") == .blitz)     // 300
        #expect(Evaluation.classifySpeed(timeControl: "600+0") == .rapid)     // 600
        #expect(Evaluation.classifySpeed(timeControl: "1800+0") == .classical) // 1800
    }

    @Test("correspondence and unknown fallbacks")
    func fallbacks() {
        #expect(Evaluation.classifySpeed(timeControl: "1/259200") == .correspondence)
        #expect(Evaluation.classifySpeed(timeControl: "-") == .correspondence)
        #expect(Evaluation.classifySpeed(timeControl: nil, event: "Rated Blitz game") == .blitz)
        #expect(Evaluation.classifySpeed(timeControl: "?", event: "Casual Rapid game") == .rapid)
        #expect(Evaluation.classifySpeed(timeControl: nil, event: "Friendly game") == .unknown)
    }
}
