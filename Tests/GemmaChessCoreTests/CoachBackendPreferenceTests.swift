//  CoachBackendPreferenceTests.swift

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("CoachBackendPreference")
struct CoachBackendPreferenceTests {

    private static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CoachBackendPreferenceTests.\(UUID().uuidString)")!
    }

    @Test("defaults to .managed when nothing has been set")
    func defaultsToManaged() {
        #expect(CoachBackendPreference.current(defaults: Self.scratchDefaults()) == .managed)
    }

    @Test("set persists and round-trips")
    func setPersists() {
        let defaults = Self.scratchDefaults()
        CoachBackendPreference.set(.byok, defaults: defaults)
        #expect(CoachBackendPreference.current(defaults: defaults) == .byok)
        CoachBackendPreference.set(.managed, defaults: defaults)
        #expect(CoachBackendPreference.current(defaults: defaults) == .managed)
    }

    @Test("malformed stored value falls back to .managed")
    func malformedValueFallsBack() {
        let defaults = Self.scratchDefaults()
        defaults.set("not-a-real-choice", forKey: "coach.backendPreference")
        #expect(CoachBackendPreference.current(defaults: defaults) == .managed)
    }
}
