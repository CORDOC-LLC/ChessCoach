//  ManagedCoachStore.swift
//  Configuration for the managed (paid-tier, developer-hosted) coach backend.
//
//  The backend URL and debug bypass token here remain local-testing/TestFlight
//  scaffolding (see each property's own header). `appUserId()` reads
//  RevenueCat's `Purchases.shared.appUserID` once the SDK is configured
//  (real subscriber identity, tied to receipts) and falls back to a generated,
//  persisted UUID before that (e.g. SPM unit tests, or a build that never
//  calls `ProEntitlementStore.configure`) -- nothing else in ManagedCoach
//  needs to change, since both are read via a closure.

import Foundation
import RevenueCat
#if canImport(Security)
import Security
#endif

/// The canonical chesscoach-gateway deployment, on the project's own domain
/// (api.chesscoach.im) rather than the raw *.vercel.app URL. Offered in
/// Coach Settings as a one-tap fill-in — never applied automatically, since
/// this is still the debug/local-testing path (see this file's header) and
/// nothing should change behavior without the user explicitly saving it.
public let managedCoachProductionURL = "https://api.chesscoach.im"

/// A Gateway model the developer can pick for local testing (KTD-3: real
/// subscribers never get this choice — see ManagedCoach's `debugModel`).
/// Slugs must match `lib/pricing.ts` in chesscoach-gateway for the Usage &
/// Cost screen's estimates to mean anything; keep the two in sync by hand.
public struct ManagedModelOption: Identifiable, Equatable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let displayName: String
    public let hint: String

    public init(slug: String, displayName: String, hint: String) {
        self.slug = slug; self.displayName = displayName; self.hint = hint
    }

    public static let flashLite = ManagedModelOption(
        slug: "google/gemini-2.5-flash-lite", displayName: "Gemini Flash Lite", hint: "Cheapest, fastest")
    public static let flash = ManagedModelOption(
        slug: "google/gemini-2.5-flash", displayName: "Gemini Flash", hint: "Balanced")
    public static let pro = ManagedModelOption(
        slug: "google/gemini-2.5-pro", displayName: "Gemini Pro", hint: "Most capable, priciest")
    public static let claudeHaiku = ManagedModelOption(
        slug: "anthropic/claude-haiku-4.5", displayName: "Claude Haiku", hint: "Alternative provider")

    /// "Server default" isn't a real slug — sending no override at all lets
    /// the backend's own CHESSCOACH_PRIMARY_MODEL decide, same as production.
    public static let serverDefault = ManagedModelOption(
        slug: "", displayName: "Server default", hint: "Whatever the backend is configured for")

    public static let all: [ManagedModelOption] = [.serverDefault, .flashLite, .flash, .pro, .claudeHaiku]
}

public enum ManagedCoachStore {
    private static let backendURLKey = "managedCoach.backendURL"
    private static let appUserIdKey = "managedCoach.debugAppUserId"
    private static let debugModelKey = "managedCoach.debugModel"
    private static let service = "com.cordoc.gemmachess.managedCoachDebug"
    private static let debugTokenAccount = "debug-token"

    /// The chosen model override, or nil to let the server decide (its own
    /// CHESSCOACH_PRIMARY_MODEL — the same thing a real subscriber gets).
    public static func loadDebugModel() -> String? {
        let stored = UserDefaults.standard.string(forKey: debugModelKey)
        return (stored?.isEmpty ?? true) ? nil : stored
    }

    public static func saveDebugModel(_ slug: String?) {
        if let slug, !slug.isEmpty {
            UserDefaults.standard.set(slug, forKey: debugModelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: debugModelKey)
        }
    }

    /// The chesscoach-gateway deployment base URL (e.g.
    /// `https://chesscoach-gateway.vercel.app`), or nil when not configured --
    /// `ManagedCoach.availability` reports `.unavailable` in that case.
    ///
    /// On TestFlight, falls back to the production deployment automatically
    /// (no user configuration needed) -- see `loadDebugToken()`'s header for
    /// why this is safe/expected only on that channel.
    public static func loadBackendURL() -> String? {
        if let saved = UserDefaults.standard.string(forKey: backendURLKey), !saved.isEmpty {
            return saved
        }
        return BuildChannel.current == .testFlight ? managedCoachProductionURL : nil
    }

    public static func saveBackendURL(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: backendURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: backendURLKey)
        }
    }

    /// RevenueCat's subscriber identity once the SDK is configured (real
    /// installs); otherwise a generated, persisted UUID so ledger/quota
    /// testing is still consistent across app launches (unit tests, or a
    /// build that never calls `ProEntitlementStore.configure`).
    public static func appUserId() -> String {
        if Purchases.isConfigured {
            return Purchases.shared.appUserID
        }
        if let existing = UserDefaults.standard.string(forKey: appUserIdKey) {
            return existing
        }
        let generated = "debug-\(UUID().uuidString)"
        UserDefaults.standard.set(generated, forKey: appUserIdKey)
        return generated
    }

    /// Set once at app launch from the app target's gitignored, generated
    /// `ManagedCoachSecrets.swift` (see `scripts/gen-project.sh`) -- this
    /// package never contains the secret itself, only this injection point.
    nonisolated(unsafe) private static var injectedTestFlightToken: String?

    /// Wires the TestFlight-only managed-coach debug token in from the app
    /// target. Call once, at launch (see `GemmaChessApp.swift`). No-op for
    /// any build that doesn't call it (local dev running from Xcode/SPM
    /// tests never does) -- `loadDebugToken()` simply has nothing to fall
    /// back to in that case.
    public static func configureTestFlightToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        injectedTestFlightToken = trimmed.isEmpty ? nil : trimmed
    }

    /// The debug bypass token (Keychain — it's a credential, not a preference:
    /// possessing it skips the backend's real entitlement check entirely).
    ///
    /// On TestFlight, falls back to `injectedTestFlightToken` (see
    /// `configureTestFlightToken(_:)`, sourced from `local.env`'s
    /// `MANAGED_TESTFLIGHT_TOKEN` at build time -- see `scripts/gen-project.sh`).
    /// This lets TestFlight testers use the managed coach against the
    /// developer's own Gemini budget with zero setup, ahead of RevenueCat
    /// being wired up (see chesscoach-gateway's `entitlementGate.ts`).
    /// Deliberately gated to `.testFlight` only: App Store production must
    /// go through a real entitlement check once RevenueCat lands, and this
    /// token is a SHARED secret extractable from the compiled binary --
    /// acceptable for a capped-quota beta, never for production. Rotate
    /// `CHESSCOACH_DEBUG_BYPASS_TOKEN` (server) + `MANAGED_TESTFLIGHT_TOKEN`
    /// (local.env) together if abused.
    public static func loadDebugToken() -> String? {
        if let saved = loadUserDebugToken(), !saved.isEmpty {
            return saved
        }
        guard BuildChannel.current == .testFlight else { return nil }
        return injectedTestFlightToken
    }

    private static func loadUserDebugToken() -> String? {
        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: debugTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeValue(forKey: kSecReturnData as String)
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
        #else
        return nil
        #endif
    }

    public static func saveDebugToken(_ token: String?) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: debugTokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        #endif
    }
}
