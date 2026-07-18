//  PuzzleRatingStoreTests.swift
//  Hand-computed Elo-lite math (K = 24, default rating = 1200, floor = 400):
//  expected = 1 / (1 + 10^((puzzleRating - userRating) / 400))
//  delta = K * (actual - expected), rounded to the nearest Int.
//
//  From a userRating of 1200:
//   - puzzle rated 1400 (above), correct: diff=0.5, 10^0.5=3.1623,
//     expected=0.2402, delta=24*(0.7598)=18.24 -> +18 -> 1218
//   - puzzle rated 1000 (below), correct: diff=-0.5, 10^-0.5=0.3162,
//     expected=0.7599, delta=24*(0.2401)=5.76 -> +6 -> 1206
//   - puzzle rated 1000 (below), wrong: same expected 0.7599,
//     delta=24*(-0.7599)=-18.24 -> -18 -> 1182
//   - puzzle rated 1400 (above), wrong: same expected 0.2402,
//     delta=24*(-0.2402)=-5.76 -> -6 -> 1194

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("PuzzleRatingStore")
struct PuzzleRatingStoreTests {

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PuzzleRatingStoreTests-\(UUID().uuidString)")!
    }

    @Test("fresh install starts at the default rating")
    func freshInstallDefault() {
        let defaults = scratchDefaults()
        #expect(PuzzleRatingStore.currentRating(defaults: defaults) == PuzzleRatingStore.defaultRating)
    }

    @Test("correct answer on a harder puzzle gains more than correct on an easier one")
    func correctGainsMoreAgainstHarderPuzzle() {
        let harderDefaults = scratchDefaults()
        let newRatingHarder = PuzzleRatingStore.update(puzzleRating: 1400, correct: true, defaults: harderDefaults)
        let gainHarder = newRatingHarder - PuzzleRatingStore.defaultRating
        #expect(gainHarder == 18)

        let easierDefaults = scratchDefaults()
        let newRatingEasier = PuzzleRatingStore.update(puzzleRating: 1000, correct: true, defaults: easierDefaults)
        let gainEasier = newRatingEasier - PuzzleRatingStore.defaultRating
        #expect(gainEasier == 6)

        #expect(gainHarder > gainEasier)
    }

    @Test("wrong answer on an easier puzzle loses more than wrong on a harder one")
    func wrongLosesMoreAgainstEasierPuzzle() {
        let easierDefaults = scratchDefaults()
        let newRatingEasier = PuzzleRatingStore.update(puzzleRating: 1000, correct: false, defaults: easierDefaults)
        let lossEasier = PuzzleRatingStore.defaultRating - newRatingEasier
        #expect(lossEasier == 18)

        let harderDefaults = scratchDefaults()
        let newRatingHarder = PuzzleRatingStore.update(puzzleRating: 1400, correct: false, defaults: harderDefaults)
        let lossHarder = PuzzleRatingStore.defaultRating - newRatingHarder
        #expect(lossHarder == 6)

        #expect(lossEasier > lossHarder)
    }

    @Test("repeated correct answers on similarly-rated puzzles trend upward and converge")
    func repeatedCorrectAnswersConverge() {
        let defaults = scratchDefaults()
        let puzzleRating = 1300
        var previous = PuzzleRatingStore.defaultRating
        var deltas: [Int] = []
        for _ in 0..<20 {
            let updated = PuzzleRatingStore.update(puzzleRating: puzzleRating, correct: true, defaults: defaults)
            deltas.append(updated - previous)
            previous = updated
        }
        // Trending upward the whole way.
        #expect(deltas.allSatisfy { $0 >= 0 })
        #expect(previous > PuzzleRatingStore.defaultRating)
        // Converging, not diverging: an unbroken win streak against a fixed
        // puzzle rating has no equilibrium value (each win still nudges the
        // rating up), but the increments themselves shrink as the gap
        // narrows -- the back half moves much less than the front half.
        let firstHalf = deltas.prefix(10).reduce(0, +)
        let secondHalf = deltas.suffix(10).reduce(0, +)
        #expect(secondHalf < firstHalf)
        #expect(deltas.first! > deltas.last!)
    }

    @Test("rating never drops below the floor on a long losing streak")
    func floorHoldsUnderLosingStreak() {
        let defaults = scratchDefaults()
        // Start near the floor and keep failing very easy puzzles, which
        // pushes hardest against the floor.
        defaults.set(PuzzleRatingStore.floor + 20, forKey: "puzzles.rating")
        for _ in 0..<50 {
            let updated = PuzzleRatingStore.update(puzzleRating: 100, correct: false, defaults: defaults)
            #expect(updated >= PuzzleRatingStore.floor)
        }
        #expect(PuzzleRatingStore.currentRating(defaults: defaults) == PuzzleRatingStore.floor)
    }

    @Test("persisted rating survives a store reload")
    func persistsAcrossReload() {
        let defaults = scratchDefaults()
        let updated = PuzzleRatingStore.update(puzzleRating: 1400, correct: true, defaults: defaults)
        #expect(PuzzleRatingStore.currentRating(defaults: defaults) == updated)
    }
}
