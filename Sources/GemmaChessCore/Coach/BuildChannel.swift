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
//  Detection matches the same technique already proven in production on
//  DictaWiz (FreeVoiceReaderApp/StoreKitManager.isTestFlight): check
//  `appStoreReceiptURL`'s filename directly, with NO `FileManager.fileExists`
//  guard -- that extra existence check was this file's original bug. It's
//  possible for a genuine TestFlight/App Store install to have a receipt URL
//  whose backing file isn't yet materialized on disk at the moment this
//  property is first read, and requiring it caused real TestFlight installs
//  to be silently misreported as `.local`. The filename alone (nil for a
//  local Xcode/devicectl install, "sandboxReceipt" for TestFlight, "receipt"
//  for App Store) is reliable without that check. Local vs. non-local is
//  cross-checked against build configuration (`#if DEBUG`), since a local
//  `xcodebuild build` is always Debug while archives (TestFlight/App Store,
//  via `scripts/upload-testflight.sh`) are always Release -- this also
//  guards against a Debug-configuration receipt quirk being misread as a
//  real distribution channel.

import Foundation

public enum BuildChannel: Equatable, Sendable {
    case local
    case testFlight
    case appStore

    public static var current: BuildChannel {
        #if DEBUG
        return .local
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? .testFlight : .appStore
        #endif
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
