//  PuzzleThemeBandingTests.swift
//  Pure tests for `PuzzleRatingBand.band(forMinRating:)` -- the function
//  `PuzzlesView` uses to group themes into Beginner/Intermediate/Advanced/
//  Other `DisclosureGroup` sections (see `docs/plans/
//  2026-07-19-004-feat-puzzles-lessons-redesign-plan.md`, KTD-1). No view
//  rendering here, just the banding math.

import Foundation
import Testing
@testable import GemmaChessCore

struct PuzzleThemeBandingTests {

    @Test func belowFiveHundredIsBeginner() {
        #expect(PuzzleRatingBand.band(forMinRating: 399) == .beginner)
    }

    @Test func fiveHundredIsIntermediate() {
        // Lower boundary of Intermediate is inclusive.
        #expect(PuzzleRatingBand.band(forMinRating: 500) == .intermediate)
    }

    @Test func justBelowSixFiftyIsStillIntermediate() {
        #expect(PuzzleRatingBand.band(forMinRating: 649) == .intermediate)
    }

    @Test func sixFiftyIsAdvanced() {
        // Lower boundary of Advanced is inclusive.
        #expect(PuzzleRatingBand.band(forMinRating: 650) == .advanced)
    }

    @Test func wellAboveSixFiftyIsAdvanced() {
        #expect(PuzzleRatingBand.band(forMinRating: 736) == .advanced)
    }

    @Test func missingRatingIsOther() {
        #expect(PuzzleRatingBand.band(forMinRating: nil) == .other)
    }

    /// Verifies against the real bundled catalog's 20 themes (minRating
    /// values ranging 399-736 per the plan) that the three real bands are
    /// all non-empty and sum to 20 -- without hardcoding which theme lands
    /// in which band, so this stays resilient to future rating recuration.
    @Test func realBundledCatalogSplitsIntoThreeNonEmptyBands() throws {
        let catalog = try #require(PuzzleDownloadStore.bundledCatalog)

        #expect(catalog.themes.count == 20)

        var counts: [PuzzleRatingBand: Int] = [:]
        for theme in catalog.themes {
            counts[theme.ratingBand, default: 0] += 1
        }

        let beginnerCount = counts[.beginner] ?? 0
        let intermediateCount = counts[.intermediate] ?? 0
        let advancedCount = counts[.advanced] ?? 0
        let otherCount = counts[.other] ?? 0

        #expect(beginnerCount > 0)
        #expect(intermediateCount > 0)
        #expect(advancedCount > 0)
        #expect(otherCount == 0)
        #expect(beginnerCount + intermediateCount + advancedCount + otherCount == 20)
    }
}
