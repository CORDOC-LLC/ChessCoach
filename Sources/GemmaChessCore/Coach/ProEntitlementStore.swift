//  ProEntitlementStore.swift
//  Wraps the RevenueCat Purchases SDK: configures it at launch, tracks whether
//  the "pro" entitlement is active, fetches the current offering's packages
//  for PaywallView, and drives purchase/restore. This is the ONLY place in
//  the app that talks to RevenueCat directly -- everything else (ManagedCoach,
//  ManagedCoachStore, PaywallView) goes through this store.
//
//  Entitlement enforcement for API calls still happens server-side in
//  chesscoach-gateway (RevenueCat webhook -> Neon, checked per-request) --
//  `isProActive` here is purely a client-side UI signal (show the paywall vs.
//  the coach UI) and must never be trusted as the actual authorization check.

import Foundation
import RevenueCat

/// Thrown by `requireProOrThrow()` when the running channel requires an
/// active Pro entitlement (see `BuildChannel.requiresProEntitlement`) and
/// the caller doesn't have one. A distinct type -- not `CoachError` -- so
/// call sites can tell "not entitled" apart from a generic backend/network
/// failure and present `PaywallView` specifically, instead of a generic
/// error message.
public struct ProRequiredError: Error, Equatable, Sendable {
    public init() {}

    /// A short, user-facing explanation, for call sites that fold this into
    /// an existing generic error-message slot (e.g. `PlayViewModel.lastCoachError`)
    /// rather than presenting `PaywallView` directly.
    public var message: String { "ChessCoach Pro subscription required." }
}

@MainActor
@Observable
public final class ProEntitlementStore {
    public static let shared = ProEntitlementStore()

    /// Must match the entitlement identifier created in the RevenueCat
    /// dashboard ("pro") and the products attached to it.
    public static let entitlementID = "pro"

    /// The lifetime Full Game Review unlock's entitlement -- deliberately
    /// SEPARATE from `entitlementID`, not shared. Pro and the lifetime
    /// purchase grant different capability sets (Pro includes the LLM coach
    /// features; the lifetime purchase does not), so sharing one entitlement
    /// would silently grant lifetime buyers LLM access. Must match the
    /// entitlement identifier created in the RevenueCat dashboard.
    public static let lifetimeReviewEntitlementID = "review_lifetime"

    /// Master kill-switch for selling the Pro subscription -- distinct from
    /// entitlement gating. Set `false` to stop offering NEW Pro purchases
    /// (e.g. while its LLM coach quality is being evaluated) without
    /// touching entitlement logic: existing checks (`effectiveIsProActive`,
    /// `requireProOrThrow`) are completely unaffected, so a real Pro
    /// subscriber would keep working normally regardless of this flag.
    /// Only gates the PURCHASE path -- see `PaywallView`, which shows a
    /// "not available yet" state instead of the plan picker when this is
    /// `false`. Currently `true` (Pro sale is active); flip back to `false`
    /// if Pro purchasing needs to pause again.
    public static let proSaleEnabled = true

    public private(set) var isProActive = false
    /// Whether the lifetime Full Game Review unlock is active, from RevenueCat's
    /// `lifetimeReviewEntitlementID`. Independent of `isProActive` -- a lifetime
    /// buyer who is NOT a Pro subscriber has `isProActive == false` here.
    public private(set) var hasLifetimeReviewUnlock = false
    public private(set) var offerings: Offerings?
    public private(set) var isLoadingOfferings = false
    public private(set) var lastError: String?

    /// QA-only override for local/TestFlight builds: local and TestFlight
    /// otherwise bypass Pro-gating unconditionally (see `BuildChannel`'s
    /// header), which means the paywall can never actually trigger there --
    /// there was no way to test the free-tier experience without an App
    /// Store build. `.free` forces gating on as if this were App Store
    /// production with no subscription (paywall shows); `.pro` forces the
    /// entitled experience explicitly; `.off` (default) is today's real
    /// behavior, unchanged.
    ///
    /// Safety: this can never affect a real App Store customer, redundantly --
    /// (1) the Settings UI that exposes it is hidden outside local/TestFlight
    /// (`BuildChannel.current != .appStore`), and (2) `effectiveIsProActive(for:)`
    /// and `requireProOrThrow` both ignore it entirely once `channel == .appStore`,
    /// regardless of what's persisted. A plain `@Observable` stored property
    /// (not a UserDefaults-computed one) so SwiftUI actually re-renders when
    /// a Settings picker changes it; `didSet` mirrors the value into
    /// `UserDefaults` so the choice survives a relaunch.
    public enum DebugProSimulation: String, CaseIterable, Sendable {
        case off, free, lifetime, pro
    }

    private static let debugProSimulationKey = "debug.proSimulation"

    public var debugProSimulation: DebugProSimulation = {
        guard let raw = UserDefaults.standard.string(forKey: ProEntitlementStore.debugProSimulationKey) else {
            return .off
        }
        return DebugProSimulation(rawValue: raw) ?? .off
    }() {
        didSet {
            if debugProSimulation == .off {
                UserDefaults.standard.removeObject(forKey: Self.debugProSimulationKey)
            } else {
                UserDefaults.standard.set(debugProSimulation.rawValue, forKey: Self.debugProSimulationKey)
            }
        }
    }

    private init() {}

    /// Call once at app launch (iOS only -- see `GemmaChessApp.init()`).
    /// No-op if already configured, so repeated calls (e.g. SwiftUI preview
    /// re-inits) are harmless.
    public func configure(apiKey: String) {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        Task { await refreshCustomerInfo() }
    }

    public func refreshCustomerInfo() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            isProActive = info.entitlements[Self.entitlementID]?.isActive == true
            hasLifetimeReviewUnlock = info.entitlements[Self.lifetimeReviewEntitlementID]?.isActive == true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func loadOfferings() async {
        guard Purchases.isConfigured else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        do {
            offerings = try await Purchases.shared.offerings()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        isProActive = result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
        hasLifetimeReviewUnlock = result.customerInfo.entitlements[Self.lifetimeReviewEntitlementID]?.isActive == true
    }

    public func restore() async throws {
        let info = try await Purchases.shared.restorePurchases()
        isProActive = info.entitlements[Self.entitlementID]?.isActive == true
        hasLifetimeReviewUnlock = info.entitlements[Self.lifetimeReviewEntitlementID]?.isActive == true
    }

    // MARK: Uniform Pro-entitlement gate (U1)

    /// The single, uniform Pro-entitlement check -- call this at the top of
    /// every code path that reaches ChessCoach's backend (coach chat, hint
    /// rationale, board-scan vision, end-of-game summary), replacing the
    /// scattered/incomplete per-screen checks that predate this. A no-op on
    /// any channel that doesn't require the entitlement at all (local/
    /// TestFlight dev builds bypass unconditionally, unchanged from today --
    /// see `BuildChannel.requiresProEntitlement`'s header for why); on
    /// App Store production, throws `ProRequiredError` unless `isProActive`
    /// is true.
    ///
    /// `channel` defaults to `.current` but is overridable so tests can
    /// drive both branches deterministically without needing a real
    /// distribution channel.
    public func requireProOrThrow(channel: BuildChannel = .current) throws {
        guard effectiveIsProActive(for: channel) else { throw ProRequiredError() }
    }

    /// Pure/static form of the same check, taking `isProActive` explicitly.
    /// `isProActive` is otherwise `private(set)` on the singleton (only ever
    /// changed by a real purchase/restore/refresh) -- this lets tests exercise
    /// both entitlement states without driving RevenueCat. Deliberately does
    /// NOT consult `debugProSimulation` -- it's a pure function of its
    /// arguments, used directly by tests that already drive both inputs.
    public nonisolated static func requireProOrThrow(channel: BuildChannel, isProActive: Bool) throws {
        guard channel.requiresProEntitlement else { return }
        guard isProActive else { throw ProRequiredError() }
    }

    /// Whether Pro features should actually be unlocked right now, folding
    /// in the channel bypass (local/TestFlight normally always-Pro), the
    /// real RevenueCat-driven `isProActive`, and -- when set and the channel
    /// isn't App Store -- `debugProSimulation`. This is the ONE predicate UI
    /// call sites should read to decide "show the paywall vs. the Pro
    /// experience"; `isProActive` itself stays raw/real for the handful of
    /// call sites (post-purchase/restore dismissal in `PaywallView`) that
    /// deliberately want the true entitlement regardless of any simulation.
    public func effectiveIsProActive(for channel: BuildChannel = .current) -> Bool {
        let sim = debugProSimulation
        if sim != .off, channel != .appStore {
            return sim == .pro
        }
        return !channel.requiresProEntitlement || isProActive
    }

    /// Whether Review's full-move analysis should be unlocked -- Pro OR the
    /// lifetime purchase, either one is sufficient (Pro is a strict superset).
    /// Mirrors `effectiveIsProActive`'s shape exactly, including the
    /// debug-simulation override and the App Store production safety guarantee.
    ///
    /// Accepted risk, documented explicitly: unlike `isProActive` (a UI signal
    /// backed by chesscoach-gateway's independent server-side entitlement check
    /// for every LLM call), this predicate has NO server backstop anywhere --
    /// Review's gating is entirely local/on-device with no network call. A
    /// client-side bypass (jailbreak, runtime patching) gets full paid Review
    /// content. Consciously accepted given the lifetime purchase's low price
    /// and the fact the content is already computed locally and non-confidential
    /// either way -- do not assume this has the same server-side parity `pro` does.
    public func effectiveHasFullReviewAccess(for channel: BuildChannel = .current) -> Bool {
        let sim = debugProSimulation
        if sim != .off, channel != .appStore {
            return sim == .pro || sim == .lifetime
        }
        return !channel.requiresProEntitlement || isProActive || hasLifetimeReviewUnlock
    }
}
