//  BuildChannel.swift
//  Which distribution channel this running binary came through -- determines
//  which coach backends are even offered:
//    - local (Xcode/devicectl install, no App Store receipt): both ChessCoach
//      Pro (debug backend URL/token) and Gemini BYOK, for development.
//    - testFlight (sandboxReceipt): Gemini BYOK only. Keeps external beta
//      testers off the not-yet-launched RevenueCat purchase flow entirely --
//      they just paste their own key.
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
        switch self {
        case .local, .appStore: return true
        case .testFlight: return false
        }
    }
}
