//  BuildChannelTests.swift
//  Which coach backends each distribution channel allows -- TestFlight is
//  BYOK-only (no paywall surface at all), App Store production is managed-
//  only (no BYOK), local dev gets both.

import Testing
@testable import GemmaChessCore

@Suite("BuildChannel")
struct BuildChannelTests {

    @Test("local dev allows both BYOK and the managed coach")
    func localAllowsBoth() {
        #expect(BuildChannel.local.allowsGeminiBYOK)
        #expect(BuildChannel.local.allowsManagedCoach)
    }

    @Test("TestFlight is BYOK-only -- no managed/paywall surface")
    func testFlightIsBYOKOnly() {
        #expect(BuildChannel.testFlight.allowsGeminiBYOK)
        #expect(!BuildChannel.testFlight.allowsManagedCoach)
    }

    @Test("App Store production is managed-only -- no BYOK")
    func appStoreIsManagedOnly() {
        #expect(!BuildChannel.appStore.allowsGeminiBYOK)
        #expect(BuildChannel.appStore.allowsManagedCoach)
    }

    @Test("CoachOrchestrator.defaultBackends respects each channel")
    func defaultBackendsCountPerChannel() {
        // Local: ManagedCoach + GeminiCoach.
        #expect(CoachOrchestrator.defaultBackends(channel: .local).count == 2)
        // TestFlight: GeminiCoach only.
        #expect(CoachOrchestrator.defaultBackends(channel: .testFlight).count == 1)
        // App Store: ManagedCoach only.
        #expect(CoachOrchestrator.defaultBackends(channel: .appStore).count == 1)
    }
}
