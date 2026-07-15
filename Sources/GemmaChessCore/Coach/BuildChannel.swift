//  BuildChannel.swift
//  Which distribution channel this running binary came through -- determines
//  which coach backends are even offered:
//    - local (Xcode/devicectl install, no App Store receipt): both ChessCoach
//      Pro (debug backend URL/token) and Gemini BYOK, for development.
//    - testFlight (sandboxReceipt): BOTH ChessCoach Pro (auto-configured via
//      a baked-in debug-bypass token against the developer's own Gemini
//      budget -- see ManagedCoachStore.loadDebugToken()) and Gemini BYOK.
//      No paywall surface: the managed coach "just works" for testers with
//      zero setup, and BYOK stays available as an alternative. This is
//      pre-RevenueCat scaffolding -- once the subscription flow lands, this
//      may tighten to match App Store production.
//    - appStore (receipt): ChessCoach Pro (managed, RevenueCat-entitled) only.
//      No BYOK in production -- the whole point is the subscription.
//
//  Detection is the standard technique: `Bundle.main.appStoreReceiptURL`'s
//  last path component is "sandboxReceipt" for TestFlight (and Xcode's own
//  StoreKit testing) and "receipt" for a real App Store install; a
//  Xcode/devicectl development install has no receipt file at all.

import Foundation

public enum BuildChannel: Equatable, Sendable {
    case local
    case testFlight
    case appStore

    /// `appStoreReceiptURL` is deprecated in favor of StoreKit 2's async
    /// `AppTransaction.shared`/`.environment` -- deliberately not using that
    /// here: this needs to be a plain synchronous property usable from
    /// CoachOrchestrator's init and view bodies, and the receipt-URL filename
    /// trick still works correctly for exactly this purpose (channel
    /// detection, not entitlement verification).
    public static var current: BuildChannel {
        guard let url = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return .local }
        return url.lastPathComponent == "sandboxReceipt" ? .testFlight : .appStore
    }

    /// Whether the user's own Gemini API key (BYOK) should be offered at all.
    public var allowsGeminiBYOK: Bool {
        switch self {
        case .local, .testFlight: return true
        case .appStore: return false
        }
    }

    /// Whether the managed ChessCoach Pro backend should be offered at all.
    public var allowsManagedCoach: Bool {
        true
    }

    /// Whether pro-gated features (coach chat, board scan) should check
    /// `ProEntitlementStore.isProActive` before running and show the paywall
    /// instead when it's false. Only App Store production actually gates --
    /// local and TestFlight already get ChessCoach Pro without a
    /// subscription (see this file's header).
    public var requiresProEntitlement: Bool { self == .appStore }
}
