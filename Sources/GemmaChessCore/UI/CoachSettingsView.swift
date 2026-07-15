//  CoachSettingsView.swift
//  Optional Gemini API key entry, plus the managed coach (ChessCoach Pro) config.
//  With neither configured, the app has engine-only review — no coach backend
//  runs on-device (on-device Foundation Models/Gemma were tried and dropped for
//  quality reasons). Stockfish still decides every grade, best move, and
//  evaluation regardless of which coach backend is configured; the coach only
//  writes about what the engine already computed.

import SwiftUI

public struct CoachSettingsView: View {
    /// Which sections even apply -- see `BuildChannel`. Local dev builds get
    /// both ChessCoach Pro (debug config) and Gemini BYOK; TestFlight gets
    /// BYOK only; App Store production gets ChessCoach Pro only (no BYOK --
    /// the subscription is the point).
    let channel: BuildChannel

    @State private var apiKey: String = GeminiKeyStore.load() ?? ""
    @State private var model: String = GeminiKeyStore.loadModel()
    @State private var saved = false

    // Managed coach (ChessCoach Pro) — debug/local-testing config, ahead of
    // RevenueCat being wired up. See ManagedCoachStore's header comment.
    @State private var backendURL: String = ManagedCoachStore.loadBackendURL() ?? ""
    @State private var debugToken: String = ManagedCoachStore.loadDebugToken() ?? ""
    @State private var debugModel: String = ManagedCoachStore.loadDebugModel() ?? ""
    @State private var managedSaved = false
    @Environment(ThemeStore.self) private var themeStore
    @State private var proStore = ProEntitlementStore.shared
    @State private var showPaywall = false

    /// Only meaningful when `offersChoice` -- which backend answers. Persisted
    /// via `CoachBackendPreference`; see that type for why this needs to be an
    /// explicit, user-driven choice rather than a fixed priority order.
    @State private var backendChoice: CoachBackendChoice = CoachBackendPreference.current()

    /// Whether this channel even offers a choice between the two backends
    /// (local dev and TestFlight do; App Store production is managed-only).
    private var offersChoice: Bool { channel.allowsManagedCoach && channel.allowsGeminiBYOK }

    public init(channel: BuildChannel = .current) {
        self.channel = channel
    }

    public var body: some View {
        Form {
            if offersChoice {
                Section {
                    Picker("Coach backend", selection: $backendChoice) {
                        Text("ChessCoach Pro").tag(CoachBackendChoice.managed)
                        Text("Bring your own key").tag(CoachBackendChoice.byok)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: backendChoice) { _, newValue in CoachBackendPreference.set(newValue) }
                } footer: {
                    Text(channel == .testFlight
                        ? "ChessCoach Pro works out of the box for TestFlight testers. If it's not " +
                          "responding, switch to your own Gemini key below."
                        : "Switch between the managed backend (debug-configured below) and your own Gemini key.")
                }
            }

            if channel.allowsManagedCoach, !offersChoice || backendChoice == .managed {
                managedCoachSection
            }
            if channel == .local, backendChoice == .managed,
               !debugToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelOverrideSection
            }
            if channel.allowsGeminiBYOK, !offersChoice || backendChoice == .byok {
                geminiIntroSection
                geminiKeySection
                geminiModelSection
                geminiFooterSection
            }
        }
        .navigationTitle("Coach Settings")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: ChessCoach Pro (managed)

    @ViewBuilder
    private var managedCoachSection: some View {
        Section("ChessCoach Pro") {
            if channel == .local {
                Text("For local testing before subscriptions are wired up: point at your own "
                    + "chesscoach-gateway deployment and, if it has a debug bypass token "
                    + "configured, paste that too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Backend URL (e.g. https://your-app.vercel.app)", text: $backendURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                if backendURL != managedCoachProductionURL {
                    Button("Use api.chesscoach.im") { backendURL = managedCoachProductionURL }
                        .font(.caption)
                }
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
                        .foregroundStyle(themeStore.effective.accentColor)
                }
                if ManagedCoachStore.loadBackendURL() != nil {
                    NavigationLink("Usage & Cost") { ManagedUsageView() }
                }
            } else if channel == .testFlight {
                // Auto-configured via a baked-in debug token (see
                // ManagedCoachStore.loadDebugToken()) -- no setup, no fields,
                // no paywall. Ahead of RevenueCat, this is what makes
                // TestFlight actually usable for beta testers.
                Text("ChessCoach Pro is on for TestFlight builds -- no setup needed. "
                    + "It runs against the developer's own budget while testing, so keep "
                    + "usage reasonable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink("Usage & Cost") { ManagedUsageView() }
            } else if proStore.isProActive {
                Label("ChessCoach Pro is active.", systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(themeStore.effective.accentColor)
                Button("Restore Purchases") {
                    Task { try? await proStore.restore() }
                }
                .font(.footnote)
            } else {
                Text("Subscribe to ChessCoach Pro for written coaching on every move -- no API key needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Subscribe") { showPaywall = true }
                Button("Restore Purchases") {
                    Task { try? await proStore.restore() }
                }
                .font(.footnote)
            }
        }
    }

    private var modelOverrideSection: some View {
        Section("Model override (debug only)") {
            Text("Try a different Gateway model for latency/price/accuracy comparisons. "
                + "Only takes effect with a debug bypass token above — real subscribers "
                + "always get the server's own choice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Model", selection: $debugModel) {
                ForEach(ManagedModelOption.all) { option in
                    VStack(alignment: .leading) {
                        Text(option.displayName)
                        Text(option.hint).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(option.slug)
                }
            }
            .pickerStyle(.inline)
            .onChange(of: debugModel) { _, newValue in ManagedCoachStore.saveDebugModel(newValue) }
        }
    }

    // MARK: Gemini BYOK

    private var geminiIntroSection: some View {
        Section {
            Text("Without ChessCoach Pro or a Gemini key, you still get full engine review — "
                + "Stockfish's grades, best moves, and evaluations — just no written coaching. "
                + "Adding your own free Gemini API key turns that on: the engine still decides "
                + "every grade and best move; Gemini just writes about it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var geminiKeySection: some View {
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
                    .foregroundStyle(themeStore.effective.accentColor)
            }
        }
    }

    private var geminiModelSection: some View {
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
    }

    private var geminiFooterSection: some View {
        Section {
            Text("Get a free key at aistudio.google.com/apikey. Stored in the device "
                + "Keychain, never sent anywhere but Google's Gemini API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
