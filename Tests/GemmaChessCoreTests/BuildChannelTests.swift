//  BuildChannelTests.swift
//  Every distribution channel offers the managed coach -- BYOK was retired
//  (plan 2026-07-21-002, R6).

import Testing
@testable import GemmaChessCore

@Suite("BuildChannel")
struct BuildChannelTests {

    @Test("every channel allows the managed coach")
    func allChannelsAllowManagedCoach() {
        #expect(BuildChannel.local.allowsManagedCoach)
        #expect(BuildChannel.testFlight.allowsManagedCoach)
        #expect(BuildChannel.appStore.allowsManagedCoach)
    }
}
