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

public enum ManagedCoachStore {
    private static let backendURLKey = "managedCoach.backendURL"
    private static let appUserIdKey = "managedCoach.debugAppUserId"
    private static let service = "com.cordoc.gemmachess.managedCoachDebug"
    private static let debugTokenAccount = "debug-token"

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
