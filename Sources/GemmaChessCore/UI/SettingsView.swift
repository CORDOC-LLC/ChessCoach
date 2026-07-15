//  SettingsView.swift
//  The app-wide Settings hub, reachable from a gear icon on Home and from
//  every other screen's toolbar. Consolidates the per-game Play toggles
//  (also editable from Play's own ⋯ menu mid-game -- both read/write the
//  same UserDefaults-backed PlayDisplaySettings, so they stay in sync),
//  the coach backend config, and on-device data management.

import SwiftUI

public struct SettingsView: View {
    @State private var settings = PlayDisplaySettings()
    @State private var stats = PlayStatsStore.current()
    @State private var showClearGamesConfirm = false
    @State private var showResetPuzzlesConfirm = false
    @State private var showResetStatsConfirm = false
    @State private var showAppearance = false
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var clearedGames = false
    @State private var resetPuzzles = false
    @Environment(ThemeStore.self) private var themeStore

    public init() {}

    public var body: some View {
        Form {
            Section {
                Button { showAppearance = true } label: {
                    Label("Appearance & themes", systemImage: "paintpalette.fill")
                }
            }

            if stats.totalGames > 0 {
                Section("Statistics") {
                    HStack {
                        statColumn("Wins", stats.wins, themeStore.effective.accentColor)
                        statColumn("Losses", stats.losses, .red)
                        statColumn("Draws", stats.draws, themeStore.effective.textColor.opacity(0.7))
                    }
                    Button(role: .destructive) { showResetStatsConfirm = true } label: {
                        Label("Reset statistics", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            Section {
                Stepper("Default engine strength: \(settings.defaultEngineSkill)/20",
                        value: $settings.defaultEngineSkill, in: 0...20)
            } header: {
                Text("New games")
            } footer: {
                Text("Preselected the next time you start a game -- remembers whatever you last played at.")
            }

            Section {
                Toggle(isOn: $settings.showCaptured) { Label("Captured pieces", systemImage: "trophy") }
                Toggle(isOn: $settings.showMoveList) { Label("Move list", systemImage: "list.bullet") }
                Toggle(isOn: $settings.showMoveComments) {
                    Label("Best moves", systemImage: "chart.bar.fill")
                }
                Toggle(isOn: $settings.showOpening) {
                    Label("Opening name", systemImage: "book.closed.fill")
                }
            } header: {
                Text("Play mode")
            } footer: {
                Text("These are all free -- Stockfish and the local opening book, no network involved.")
            }

            Section {
                Toggle(isOn: $settings.showCoach) {
                    Label("Coach", systemImage: "bubble.left.fill")
                }
                NavigationLink {
                    CoachSettingsView()
                } label: {
                    Label("Coach backend (ChessCoach Pro / Gemini)", systemImage: "gearshape.2")
                }
            } header: {
                Text("Coach")
            } footer: {
                Text("The written explanation, chat, and end-of-game debrief are the only things "
                    + "that use Gemini credits. Turn Coach off to keep everything else free.")
            }

            Section("On-device data") {
                Button(role: .destructive) { showClearGamesConfirm = true } label: {
                    Label("Clear all saved games", systemImage: "trash")
                }
                if clearedGames {
                    Label("Cleared.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(themeStore.effective.accentColor)
                }
                Button(role: .destructive) { showResetPuzzlesConfirm = true } label: {
                    Label("Reset puzzle progress", systemImage: "arrow.counterclockwise")
                }
                if resetPuzzles {
                    Label("Reset.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(themeStore.effective.accentColor)
                }
            }

            Section {
                Button("How ChessCoach works") { showOnboarding = true }
                NavigationLink("Open Source Licenses") { LicensesView() }
                NavigationLink("New to chess?") { BeginnersView() }
            }

            if BuildChannel.current != .appStore {
                Section {
                    Button("Preview Paywall") { showPaywall = true }
                } footer: {
                    Text("Local/TestFlight only -- lets you check the paywall's look without needing "
                        + "a real purchase flow.")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete every saved game? This can't be undone.",
            isPresented: $showClearGamesConfirm, titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                SavedGameStore.deleteAll()
                clearedGames = true
            }
        }
        .confirmationDialog(
            "Reset progress on every puzzle theme? Solved puzzles will show up again.",
            isPresented: $showResetPuzzlesConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                PuzzleProgressStore.resetAll()
                resetPuzzles = true
            }
        }
        .confirmationDialog(
            "Reset your win/loss/draw record? This can't be undone.",
            isPresented: $showResetStatsConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                PlayStatsStore.resetAll()
                stats = PlayStatsStore.current()
            }
        }
        .sheet(isPresented: $showAppearance) { AppearanceView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onFinish: { showOnboarding = false })
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onFinish: { showOnboarding = false })
                .frame(minWidth: 480, minHeight: 640)
        }
        #endif
    }

    private func statColumn(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
