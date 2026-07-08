//  CoachSettingsView.swift
//  Optional Gemini API key entry. Entirely opt-in: with no key set, the app keeps
//  using the on-device coach (Apple Foundation Models). Setting a key upgrades
//  ONLY the explanation layer to Gemini — Stockfish still decides every grade,
//  best move, and evaluation; Gemini, like every other backend, only writes.

import SwiftUI

public struct CoachSettingsView: View {
    @State private var apiKey: String = GeminiKeyStore.load() ?? ""
    @State private var model: String = GeminiKeyStore.loadModel()
    @State private var saved = false

    // Managed coach (ChessCoach Pro) — debug/local-testing config, ahead of
    // RevenueCat being wired up. See ManagedCoachStore's header comment.
    @State private var backendURL: String = ManagedCoachStore.loadBackendURL() ?? ""
    @State private var debugToken: String = ManagedCoachStore.loadDebugToken() ?? ""
    @State private var managedSaved = false

    public init() {}

    public var body: some View {
        Form {
            Section("ChessCoach Pro (managed coach — testing)") {
                Text("For local testing before subscriptions are wired up: point at your own "
                    + "chesscoach-gateway deployment and, if it has a debug bypass token "
                    + "configured, paste that too. This backend takes priority over Gemini and "
                    + "the on-device coach whenever it's configured.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Backend URL (e.g. https://your-app.vercel.app)", text: $backendURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Debug bypass token (optional)", text: $debugToken)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("Save") {
                    ManagedCoachStore.saveBackendURL(backendURL)
                    ManagedCoachStore.saveDebugToken(debugToken)
                    managedSaved = true
                }
                .disabled(backendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && ManagedCoachStore.loadBackendURL() == nil)
                if !backendURL.isEmpty || ManagedCoachStore.loadBackendURL() != nil {
                    Button("Remove", role: .destructive) {
                        backendURL = ""; debugToken = ""
                        ManagedCoachStore.saveBackendURL(nil)
                        ManagedCoachStore.saveDebugToken(nil)
                        managedSaved = true
                    }
                }
                if managedSaved {
                    Label(ManagedCoachStore.loadBackendURL() != nil ? "Saved." : "Removed.",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(GemmaTheme.accent)
                }
                if ManagedCoachStore.loadBackendURL() != nil {
                    NavigationLink("Usage & Cost") { ManagedUsageView() }
                }
            }
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
            Section("Model") {
                Picker("Model", selection: $model) {
                    ForEach(GeminiModelOption.all) { option in
                        VStack(alignment: .leading) {
                            Text(option.displayName)
                            Text(option.hint).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(option.slug)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: model) { _, newValue in GeminiKeyStore.saveModel(newValue) }
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
