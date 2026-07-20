//  SettingsView.swift
//  The app-wide Settings hub, reachable from a gear icon on Home and from
//  every other screen's toolbar. Consolidates the per-game Play toggles
//  (also editable from Play's own ⋯ menu mid-game -- both read/write the
//  same UserDefaults-backed PlayDisplaySettings, so they stay in sync),
//  the coach backend config, and on-device data management.

import SwiftUI

public struct SettingsView: View {
    @State private var settings = PlayDisplaySettings()
    /// Matches `GemmaRootView`'s own `@AppStorage` key exactly -- both read
    /// the same UserDefaults entry, so toggling this here is immediately
    /// reflected the next time the tab bar's visibility is evaluated. Off by
    /// default: the tab bar auto-hides whenever a chessboard is on screen
    /// (Play, a Puzzle/Lesson/Opening Trainer session, Review's analysis
    /// view); this is the override to keep it visible there too.
    @AppStorage("play.showTabBarWithBoard") private var showTabBarWithBoard = false
    @State private var stats = PlayStatsStore.current()
    @State private var showClearGamesConfirm = false
    @State private var showResetPuzzlesConfirm = false
    @State private var showResetStatsConfirm = false
    @State private var showResetOpeningTrainerConfirm = false
    @State private var showResetPuzzleRatingConfirm = false
    @State private var showResetLessonsConfirm = false
    @State private var showAppearance = false
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var clearedGames = false
    @State private var resetPuzzles = false
    @State private var resetOpeningTrainer = false
    @State private var resetPuzzleRating = false
    @State private var resetLessons = false
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss
    private var hasSavedGames: Bool { !SavedGameStore.loadAll().isEmpty }

    /// Invoked when a game is picked from "My Games" (see the Data & Progress
    /// section below) -- lets whichever screen presented Settings resume that
    /// game in Play mode. `dismiss()` pops this whole Settings push (and,
    /// since "My Games" is itself pushed on top of Settings, that nested push
    /// too) back to wherever Settings was opened from, so the caller's mode
    /// change is actually visible instead of sitting underneath two still-open
    /// pushed views.
    var onSelectSavedGame: ((SavedGame) -> Void)?

    public init(onSelectSavedGame: ((SavedGame) -> Void)? = nil) {
        self.onSelectSavedGame = onSelectSavedGame
    }

    public var body: some View {
        Form {
            Section {
                Button { showAppearance = true } label: {
                    Label("Appearance & themes", systemImage: "paintpalette.fill")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                Stepper("Default engine strength: \(settings.defaultEngineSkill)/20",
                        value: $settings.defaultEngineSkill, in: 0...20)
                Toggle(isOn: $settings.showCaptured) { Label("Captured pieces", systemImage: "trophy") }
                Toggle(isOn: $settings.showMoveList) { Label("Move list", systemImage: "list.bullet") }
                Toggle(isOn: $settings.showMoveComments) {
                    Label("Move review", systemImage: "chart.bar.fill")
                }
                Toggle(isOn: $settings.showOpening) {
                    Label("Opening name", systemImage: "book.closed.fill")
                }
                Toggle(isOn: $showTabBarWithBoard) {
                    Label("Tab bar with board on screen", systemImage: "rectangle.bottomthird.inset.filled")
                }
            } header: {
                Text("Play defaults")
            } footer: {
                Text("Preselected the next time you start a game -- remembers whatever you last played "
                    + "at. These are all free -- Stockfish and the local opening book, no network involved. "
                    + "The tab bar hides automatically whenever a chessboard is on screen -- turn this on "
                    + "to keep it visible there too.")
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
                if hasSavedGames {
                    NavigationLink {
                        SavedGamesView(onSelect: { saved in
                            onSelectSavedGame?(saved)
                            dismiss()
                        })
                    } label: {
                        Label("My Games", systemImage: "clock.arrow.circlepath")
                    }
                }
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
                Button(role: .destructive) { showResetPuzzleRatingConfirm = true } label: {
                    Label("Reset puzzle rating", systemImage: "arrow.counterclockwise")
                }
                if resetPuzzleRating {
                    Label("Reset.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(themeStore.effective.accentColor)
                }
                Button(role: .destructive) { showResetOpeningTrainerConfirm = true } label: {
                    Label("Reset opening trainer progress", systemImage: "arrow.counterclockwise")
                }
                if resetOpeningTrainer {
                    Label("Reset.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(themeStore.effective.accentColor)
                }
                Button(role: .destructive) { showResetLessonsConfirm = true } label: {
                    Label("Reset lesson progress", systemImage: "arrow.counterclockwise")
                }
                if resetLessons {
                    Label("Reset.", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(themeStore.effective.accentColor)
                }
            } header: {
                Text("Data & Progress")
            } footer: {
                Text("Manage what's stored on this device. Games are saved on this device only.")
            }

            Section {
                Button("How ChessCoach works") { showOnboarding = true }
                NavigationLink("Open Source Licenses") { LicensesView() }
                NavigationLink("New to chess?") { BeginnersView() }
            } header: {
                Text("About")
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
        .confirmationDialog(
            "Reset your puzzle rating back to the starting value?",
            isPresented: $showResetPuzzleRatingConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                PuzzleRatingStore.reset()
                resetPuzzleRating = true
            }
        }
        .confirmationDialog(
            "Reset lesson progress? Every lesson starts over.",
            isPresented: $showResetLessonsConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                LessonProgressStore.resetAll()
                resetLessons = true
            }
        }
        .confirmationDialog(
            "Reset opening trainer progress? Every line's familiarity starts over.",
            isPresented: $showResetOpeningTrainerConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                OpeningTrainerStore.resetAll()
                resetOpeningTrainer = true
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
