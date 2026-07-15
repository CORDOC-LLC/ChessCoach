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

@MainActor
@Observable
public final class ProEntitlementStore {
    public static let shared = ProEntitlementStore()

    /// Must match the entitlement identifier created in the RevenueCat
    /// dashboard ("pro") and the products attached to it.
    public static let entitlementID = "pro"

    public private(set) var isProActive = false
    public private(set) var offerings: Offerings?
    public private(set) var isLoadingOfferings = false
    public private(set) var lastError: String?

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
    }

    public func restore() async throws {
        let info = try await Purchases.shared.restorePurchases()
        isProActive = info.entitlements[Self.entitlementID]?.isActive == true
    }
}
