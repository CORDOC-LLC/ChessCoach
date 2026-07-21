//  ProEntitlementStoreTests.swift
//  U1: the single, uniform Pro-entitlement gate. `requireProOrThrow` is exercised
//  two ways -- the pure static form (channel + isProActive passed explicitly, so
//  both branches are deterministic without touching RevenueCat) and the instance
//  form on the real singleton (whose `isProActive` is `private(set)`, so only the
//  `channel` override is exercised there -- `isProActive` reflects real state,
//  which is false in a test binary that never configures Purchases).
//
//  Also covers `requestHint`'s relationship to the gate: since plan
//  2026-07-21-003 U2 the hint is engine-only on every tier, so a fully
//  Pro-gated coach must have NO effect on it -- the hint populates completely
//  (arrows, SAN, template rationale) and no gate error ever surfaces.

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

    // MARK: requestHint integration -- engine-only, untouched by the Pro gate

    @MainActor
    private func wait(upTo seconds: Double = 15, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    @Test("requestHint: engine-only hint fully populates behind a failing Pro gate, no error surfaces")
    func requestHintUnaffectedByProGate() async {
        let vm = PlayViewModel.forTesting(coach: proGatedOrchestrator())
        vm.requestHint()

        await wait { vm.hint?.bestUCI.isEmpty == false }

        // The whole hint (Stockfish best move + alternative + template
        // rationale) is engine-only -- it never goes near the coach backend,
        // so a failing entitlement gate can't dent it or surface an error.
        #expect(vm.hint?.bestUCI.isEmpty == false)
        #expect(vm.hint?.bestSAN.isEmpty == false)
        #expect(vm.hint?.rationale?.isEmpty == false)
        #expect(vm.lastCoachError == nil)
    }
}
