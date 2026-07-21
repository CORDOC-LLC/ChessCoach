//  CoachSettingsView.swift
//  Managed coach (ChessCoach Pro) config. With it not configured/subscribed,
//  the app has engine-only review — no coach backend runs on-device (on-device
//  Foundation Models/Gemma were tried and dropped for quality reasons).
//  Stockfish still decides every grade, best move, and evaluation regardless;
//  the coach only writes about what the engine already computed.
//
//  BYOK (a user-supplied Gemini API key) was offered here until plan
//  2026-07-21-002 (R6) retired it -- it couldn't coexist with prompts living
//  only server-side. ChessCoach Pro is now the only backend on every channel.

import SwiftUI

public struct CoachSettingsView: View {
    /// Which sections apply -- see `BuildChannel`.
    let channel: BuildChannel

    // Managed coach (ChessCoach Pro) — debug/local-testing config, ahead of
    // RevenueCat being wired up. See ManagedCoachStore's header comment.
    @State private var backendURL: String = ManagedCoachStore.loadBackendURL() ?? ""
    @State private var debugToken: String = ManagedCoachStore.loadDebugToken() ?? ""
    @State private var debugModel: String = ManagedCoachStore.loadDebugModel() ?? ""
    @State private var managedSaved = false
    @Environment(ThemeStore.self) private var themeStore
    @State private var proStore = ProEntitlementStore.shared
    @State private var showPaywall = false

    public init(channel: BuildChannel = .current) {
        self.channel = channel
    }

    public var body: some View {
        Form {
            managedCoachSection
            if channel == .local, !debugToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelOverrideSection
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
}
