//  ManagedCoachStore.swift
//  Configuration for the managed (paid-tier, developer-hosted) coach backend.
//
//  Two pieces persist here, and both are TEMPORARY scaffolding for local
//  testing before RevenueCat is wired in client-side (see plan KTD-8, unit
//  U6): the backend URL and a debug bypass token, letting the developer
//  exercise the real chesscoach-gateway deployment (Gateway, Neon ledger,
//  App Attest) end-to-end without first building the RevenueCat purchase
//  flow. Once U6 lands, `appUserId` switches to reading RevenueCat's
//  `Purchases.shared.appUserID` instead of the generated UUID here — nothing
//  else in ManagedCoach needs to change, since both are read via a closure.

import Foundation
#if canImport(Security)
import Security
#endif

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
    public static func loadBackendURL() -> String? {
        UserDefaults.standard.string(forKey: backendURLKey)
    }

    public static func saveBackendURL(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: backendURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: backendURLKey)
        }
    }

    /// A stable per-install identifier used as `appUserId` until RevenueCat
    /// (U6) replaces it with a real subscriber identity. Generated once,
    /// persisted, never regenerated — so ledger/quota testing is consistent
    /// across app launches.
    public static func debugAppUserId() -> String {
        if let existing = UserDefaults.standard.string(forKey: appUserIdKey) {
            return existing
        }
        let generated = "debug-\(UUID().uuidString)"
        UserDefaults.standard.set(generated, forKey: appUserIdKey)
        return generated
    }

    /// The debug bypass token (Keychain — it's a credential, not a preference:
    /// possessing it skips the backend's real entitlement check entirely).
    public static func loadDebugToken() -> String? {
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
