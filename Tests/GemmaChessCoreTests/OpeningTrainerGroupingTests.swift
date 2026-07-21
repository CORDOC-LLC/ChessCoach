//  OpeningTrainerGroupingTests.swift
//  Covers OpeningTrainerViewModel.groupedResults: lines sharing a family
//  (e.g. every "Queen's Pawn Game: ..." variation) land in one group,
//  families are ordered alphabetically for predictable browsing, and a
//  search query narrows the grouped results the same way it narrows the
//  flat ones.

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
@Suite("OpeningTrainerViewModel: family grouping")
struct OpeningTrainerGroupingTests {

    @Test("lines sharing a family land in one group")
    func linesShareFamilyGroup() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        // `results` no longer populates at init (the ECO parse is deferred off
        // the launch path); an empty search fills it synchronously, standing in
        // for the screen's `loadResultsIfNeeded()` on-appear load.
        vm.search("")

        // The real vendored book has multiple lines under "Queen's Pawn Game"
        // (e.g. the Accelerated London System and its sub-variations).
        let groups = vm.groupedResults
        let queensPawn = groups.first { $0.title == "Queen's Pawn Game" }
        #expect(queensPawn != nil)
        #expect((queensPawn?.lines.count ?? 0) > 1)
        #expect(queensPawn?.lines.allSatisfy { $0.family == "Queen's Pawn Game" } == true)
    }

    @Test("family groups are ordered alphabetically")
    func groupsAreAlphabetical() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.search("")   // see linesShareFamilyGroup -- results are lazy now
        let titles = vm.groupedResults.map(\.title)
        #expect(titles == titles.sorted())
    }

    @Test("a search query narrows the grouped results the same way it narrows the flat list")
    func searchNarrowsGroupedResults() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.search("Sicilian")

        let allLinesInGroups = vm.groupedResults.flatMap(\.lines)
        #expect(Set(allLinesInGroups.map(\.id)) == Set(vm.results.map(\.id)))
        #expect(!vm.groupedResults.isEmpty)
        #expect(vm.groupedResults.allSatisfy { group in
            group.lines.allSatisfy { $0.name.localizedCaseInsensitiveContains("Sicilian") || $0.eco.localizedCaseInsensitiveContains("Sicilian") }
        })
    }
}
