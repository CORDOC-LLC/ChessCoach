//  ProEntitlementStoreTests.swift
//  U1: the single, uniform Pro-entitlement gate. `requireProOrThrow` is exercised
//  two ways -- the pure static form (channel + isProActive passed explicitly, so
//  both branches are deterministic without touching RevenueCat) and the instance
//  form on the real singleton (whose `isProActive` is `private(set)`, so only the
//  `channel` override is exercised there -- `isProActive` reflects real state,
//  which is false in a test binary that never configures Purchases).
//
//  Also covers the integration point this unit is really about: `requestHint`'s
//  rationale branch surfaces `ProRequiredError` as a paywall-prompt state
//  (`lastCoachError`) instead of silently failing or crashing, while the
//  best-move arrow/SAN -- pure local Stockfish -- still populate.

import Testing
import Foundation
@testable import GemmaChessCore

/// A `CoachOrchestrator` whose Pro-entitlement gate is forced to fail --
/// `channel: .appStore` plus a test binary's real `ProEntitlementStore.shared`
/// (never configured, so `isProActive == false`) makes `requireProOrThrow`
/// actually throw `ProRequiredError`, without needing a real distribution
/// channel or a fake backend.
private func proGatedOrchestrator() -> CoachOrchestrator {
    CoachOrchestrator(coach: .mockAnswering("unused"), channel: .appStore)
}

@Suite("ProEntitlementStore: uniform Pro-gate (U1)", .serialized)
struct ProEntitlementStoreTests {

    // MARK: Static (pure) form -- both entitlement states, deterministic

    @Test("App Store channel, not entitled -> throws ProRequiredError")
    func appStoreNotEntitledThrows() {
        #expect(throws: ProRequiredError.self) {
            try ProEntitlementStore.requireProOrThrow(channel: .appStore, isProActive: false)
        }
    }

    @Test("App Store channel, entitled -> does not throw")
    func appStoreEntitledDoesNotThrow() throws {
        try ProEntitlementStore.requireProOrThrow(channel: .appStore, isProActive: true)
    }

    @Test("Local channel, not entitled -> does not throw (existing dev bypass preserved)")
    func localBypassesRegardlessOfEntitlement() throws {
        try ProEntitlementStore.requireProOrThrow(channel: .local, isProActive: false)
    }

    @Test("TestFlight channel, not entitled -> does not throw (existing dev bypass preserved)")
    func testFlightBypassesRegardlessOfEntitlement() throws {
        try ProEntitlementStore.requireProOrThrow(channel: .testFlight, isProActive: false)
    }

    // MARK: Instance form -- the real singleton, channel overridden per-call

    @MainActor
    @Test("instance form forwards to the static gate for the given channel")
    func instanceFormForwardsToStaticGate() throws {
        let store = ProEntitlementStore.shared
        // `isProActive` is false in a test binary (Purchases never configured) --
        // an App Store channel must therefore throw, and a local channel must not.
        #expect(store.isProActive == false)
        #expect(throws: ProRequiredError.self) {
            try store.requireProOrThrow(channel: .appStore)
        }
        try store.requireProOrThrow(channel: .local)
    }

    // MARK: requestHint integration -- rationale gated, best-move arrow unaffected

    @MainActor
    private func wait(upTo seconds: Double = 15, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    @Test("requestHint: gated rationale surfaces a paywall-prompt error; best move/SAN still populate")
    func requestHintSurfacesGateFailureWithoutLosingBestMove() async {
        let vm = PlayViewModel.forTesting(coach: proGatedOrchestrator())
        vm.requestHint()

        await wait { vm.hint?.bestUCI.isEmpty == false }

        // The pure-local part (Stockfish best move + a distinct alternative) is
        // unaffected by the gate -- it never goes near the coach backend.
        #expect(vm.hint?.bestUCI.isEmpty == false)
        #expect(vm.hint?.bestSAN.isEmpty == false)

        // The rationale branch hit the gate and surfaced it as a distinct,
        // user-facing message instead of silently failing or crashing.
        await wait { vm.lastCoachError != nil }
        #expect(vm.lastCoachError == ProRequiredError().message)
        #expect(vm.hint?.isLoading == false)
    }
}
