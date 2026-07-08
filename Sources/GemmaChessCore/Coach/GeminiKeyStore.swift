//  GeminiKeyStore.swift
//  Secure storage for the user's own Gemini API key. A Keychain generic-password
//  item, not UserDefaults — this is a credential, not a preference, and it must
//  survive as securely as any other secret on the device.

import Foundation
#if canImport(Security)
import Security
#endif

/// Reads/writes the user's Gemini API key in the Keychain. A cloud coach is
/// entirely opt-in: with no key stored, `GeminiCoach.availability` reports
/// `.unavailable` and the orchestrator falls through to the on-device backend.
public enum GeminiKeyStore {
    private static let service = "com.cordoc.gemmachess.gemini"
    private static let account = "api-key"

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
