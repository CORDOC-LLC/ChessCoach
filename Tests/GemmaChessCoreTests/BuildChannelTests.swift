//  BuildChannelTests.swift
//  Which coach backends each distribution channel allows -- local dev and
//  TestFlight both get BYOK + the managed coach (TestFlight's managed coach
//  is auto-configured via a baked-in debug token, no paywall surface), App
//  Store production is managed-only (no BYOK).

import Testing
@testable import GemmaChessCore

@Suite("BuildChannel")
struct BuildChannelTests {

    @Test("local dev allows both BYOK and the managed coach")
    func localAllowsBoth() {
        #expect(BuildChannel.local.allowsGeminiBYOK)
        #expect(BuildChannel.local.allowsManagedCoach)
    }

    @Test("TestFlight allows both BYOK and the managed coach -- no paywall surface")
    func testFlightAllowsBoth() {
        #expect(BuildChannel.testFlight.allowsGeminiBYOK)
        #expect(BuildChannel.testFlight.allowsManagedCoach)
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
        // TestFlight: ManagedCoach + GeminiCoach.
        #expect(CoachOrchestrator.defaultBackends(channel: .testFlight).count == 2)
        // App Store: ManagedCoach only.
        #expect(CoachOrchestrator.defaultBackends(channel: .appStore).count == 1)
    }
}
