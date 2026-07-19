//  HomeViewNavigationTests.swift
//  Covers HomeTab's stable ordering -- the bottom tab bar renders
//  HomeTab.allCases left-to-right, so an accidental reorder here would
//  silently reshuffle the bar's visual sequence.

import Testing
@testable import GemmaChessCore

@Suite("HomeTab")
struct HomeTabTests {

    @Test("allCases is ordered Home, Lessons, Openings, Puzzles")
    func allCasesOrder() {
        #expect(HomeTab.allCases == [.home, .lessons, .openings, .puzzles])
    }

    @Test("every tab has a non-empty title and SF Symbol name")
    func everyTabHasTitleAndIcon() {
        for tab in HomeTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }
}
