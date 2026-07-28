//  CoachingStyleTests.swift
//  The "Instant" coaching style promises that nothing about your game leaves
//  the device. That promise is only as good as the gate every coach network
//  call goes through, so these tests pin `coachProseEnabled` itself -- the one
//  predicate the per-move note, the debrief, and chat all check.
//
//  If a future call site checks its own ad-hoc combination instead, these tests
//  won't catch it. That's why the gate is a single property with a comment
//  saying so, rather than three repeated conditions.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("Coaching style (Instant vs Explained)")
@MainActor
struct CoachingStyleTests {

    private func makeVM(explanations: Bool, coachOn: Bool = true) -> PlayViewModel {
        let vm = PlayViewModel()
        vm.coachAvailability = .managed
        vm.coachDisplayEnabled = coachOn
        vm.explanationsEnabled = explanations
        // Dev channels don't gate on entitlement, which isolates the style
        // switch from the Pro question.
        vm.entitlementChannel = .local
        return vm
    }

    @Test("Explained lets written coaching run")
    func explainedAllowsProse() {
        #expect(makeVM(explanations: true).coachProseEnabled)
    }

    @Test("Instant blocks written coaching even for an entitled user")
    func instantBlocksProse() {
        let vm = makeVM(explanations: false)
        #expect(vm.isProEntitled)          // entitled...
        #expect(!vm.coachProseEnabled)     // ...and still no network coaching
    }

    @Test("Instant keeps the coach card itself -- ratings are not switched off")
    func instantKeepsTheCard() {
        let vm = makeVM(explanations: false)
        #expect(vm.coachEnabled)
    }

    @Test("turning the coach card off blocks prose regardless of style")
    func cardOffBlocksProse() {
        for style in [true, false] {
            #expect(!makeVM(explanations: style, coachOn: false).coachProseEnabled)
        }
    }

    @Test("an unavailable backend blocks prose even on Explained")
    func unavailableBackendBlocksProse() {
        let vm = makeVM(explanations: true)
        vm.coachAvailability = .unavailable(reason: "not configured")
        #expect(!vm.coachProseEnabled)
        #expect(!vm.coachEnabled)
    }

    @Test("a free App Store user gets no prose whichever style is selected")
    func freeUserNeverGetsProse() {
        for style in [true, false] {
            let vm = makeVM(explanations: style)
            vm.entitlementChannel = .appStore
            // No active subscription in the test environment.
            #expect(!vm.isProEntitled)
            #expect(!vm.coachProseEnabled)
        }
    }

    // MARK: Persistence

    @Test("the style persists and defaults to Explained")
    func stylePersists() {
        let suite = UserDefaults(suiteName: "CoachingStyleTests-\(UUID().uuidString)")!
        // Default is Explained so a paying user gets what they paid for.
        #expect(PlayDisplaySettings(defaults: suite).coachExplanations)

        let settings = PlayDisplaySettings(defaults: suite)
        settings.coachExplanations = false
        #expect(!PlayDisplaySettings(defaults: suite).coachExplanations)
    }
}
