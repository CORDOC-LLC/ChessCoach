//  CoachSettingsView.swift
//  Optional Gemini API key entry. Entirely opt-in: with no key set, the app keeps
//  using the on-device coach (Apple Foundation Models). Setting a key upgrades
//  ONLY the explanation layer to Gemini — Stockfish still decides every grade,
//  best move, and evaluation; Gemini, like every other backend, only writes.

import SwiftUI

public struct CoachSettingsView: View {
    @State private var apiKey: String = GeminiKeyStore.load() ?? ""
    @State private var saved = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text("ChessCoach's coach runs on-device by default (Apple Foundation Models). "
                    + "Adding your own free Gemini API key upgrades the coach's explanations — "
                    + "the engine still decides every grade and best move; Gemini just writes "
                    + "about it more clearly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Gemini API key") {
                SecureField("Paste your API key", text: $apiKey)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("Save") {
                    GeminiKeyStore.save(apiKey)
                    saved = true
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && GeminiKeyStore.load() == nil)
                if !apiKey.isEmpty || GeminiKeyStore.load() != nil {
                    Button("Remove key", role: .destructive) {
                        apiKey = ""
                        GeminiKeyStore.save(nil)
                        saved = true
                    }
                }
                if saved {
                    Label(GeminiKeyStore.load() != nil ? "Saved." : "Key removed.",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(GemmaTheme.accent)
                }
            }
            Section {
                Text("Get a free key at aistudio.google.com/apikey. Stored in the device "
                    + "Keychain, never sent anywhere but Google's Gemini API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Coach Settings")
    }
}
