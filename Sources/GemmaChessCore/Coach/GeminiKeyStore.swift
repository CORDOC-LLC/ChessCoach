//  GeminiKeyStore.swift
//  Secure storage for the user's own Gemini API key. A Keychain generic-password
//  item, not UserDefaults — this is a credential, not a preference, and it must
//  survive as securely as any other secret on the device.

import Foundation
#if canImport(Security)
import Security
#endif

/// One selectable Gemini model, with a short cost/quality hint for the settings UI.
/// Slugs are the model IDs the Gemini REST API expects; verify against
/// https://ai.google.dev/gemini-api/docs/models before adding new ones — Google
/// renames/retires tiers periodically.
public struct GeminiModelOption: Identifiable, Equatable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let displayName: String
    public let hint: String

    public init(slug: String, displayName: String, hint: String) {
        self.slug = slug; self.displayName = displayName; self.hint = hint
    }

    public static let flashLite = GeminiModelOption(
        slug: "gemini-2.5-flash-lite", displayName: "Flash Lite", hint: "Cheapest, fastest")
    public static let flash = GeminiModelOption(
        slug: "gemini-2.5-flash", displayName: "Flash", hint: "Balanced (default)")
    public static let pro = GeminiModelOption(
        slug: "gemini-2.5-pro", displayName: "Pro", hint: "Most capable, priciest")

    public static let all: [GeminiModelOption] = [.flashLite, .flash, .pro]
}

/// Reads/writes the user's Gemini API key (Keychain) and chosen model
/// (UserDefaults — not a secret). A cloud coach is entirely opt-in: with no key
/// stored, `GeminiCoach.availability` reports `.unavailable` and the orchestrator
/// falls through to the on-device backend.
public enum GeminiKeyStore {
    private static let service = "com.cordoc.gemmachess.gemini"
    private static let account = "api-key"
    private static let modelDefaultsKey = "gemini.model"

    /// The model to use for new Gemini calls: the user's saved choice, or
    /// `GeminiCoach.defaultModel` when none has been set.
    public static func loadModel() -> String {
        UserDefaults.standard.string(forKey: modelDefaultsKey) ?? GeminiModelOption.flash.slug
    }

    public static func saveModel(_ slug: String) {
        UserDefaults.standard.set(slug, forKey: modelDefaultsKey)
    }

    public static func load() -> String? {
        #if canImport(Security)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeValue(forKey: kSecReturnData as String)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
        #else
        return nil
        #endif
    }

    /// Stores the key, or deletes it when `key` is empty/nil.
    public static func save(_ key: String?) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        #endif
    }
}
