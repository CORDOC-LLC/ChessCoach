//  PlayDisplaySettingsTests.swift
//  U1 — defaults, independence of toggles, and persistence round-trip.

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
struct PlayDisplaySettingsTests {

    /// A fresh, isolated UserDefaults so tests don't touch the real domain.
    private func freshDefaults() -> UserDefaults {
        let name = "PlayDisplaySettingsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaults() {
        let s = PlayDisplaySettings(defaults: freshDefaults())
        #expect(s.showCoach == true)
        #expect(s.showCaptured == true)
        #expect(s.showMoveList == true)
        #expect(s.showOpening == true)
        #expect(s.defaultEngineSkill == 6)
    }

    @Test("default engine strength persists and is independent of the other toggles")
    func defaultEngineSkillPersists() {
        let d = freshDefaults()
        do {
            let s = PlayDisplaySettings(defaults: d)
            s.defaultEngineSkill = 14
        }
        let s2 = PlayDisplaySettings(defaults: d)
        #expect(s2.defaultEngineSkill == 14)
        #expect(s2.showCoach == true)
    }

    @Test("Coach can be turned off while the free display toggles stay on")
    func coachToggleLeavesOthersUnchanged() {
        let s = PlayDisplaySettings(defaults: freshDefaults())
        s.showCoach = false
        #expect(s.showCoach == false)
        #expect(s.showCaptured == true)
        #expect(s.showMoveList == true)
        #expect(s.showOpening == true)
    }

    @Test func persistenceRoundTrip() {
        let d = freshDefaults()
        do {
            let s = PlayDisplaySettings(defaults: d)
            s.showCoach = false
            s.showOpening = false
        }
        // A new instance over the same store re-reads the saved values.
        let s2 = PlayDisplaySettings(defaults: d)
        #expect(s2.showCoach == false)
        #expect(s2.showOpening == false)
        #expect(s2.showCaptured == true)
        #expect(s2.showMoveList == true)
    }
}
