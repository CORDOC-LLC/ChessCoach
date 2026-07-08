//  RootView.swift
//  The shared app entry. Both app shells embed `GemmaRootView()`. A Home screen
//  routes to Play mode (new game vs the engine, with live coaching) or Review mode
//  (paste/import a game and study it). Each mode runs in the navigation stack.

import SwiftUI

/// Retained for source compatibility with the app shells; the root is stack-based.
public enum GemmaLayoutStyle: Sendable {
    case automatic, column, split
}

public struct GemmaRootView: View {
    @State private var review = ReviewViewModel()
    @State private var play = PlayViewModel()
    @State private var mode: Mode = .home
    /// Whether the next `.play` route should skip the new-game setup form and
    /// go straight to the live game -- true when `play` was just `load(_:)`ed
    /// from a saved game (Resume, or a pick from My Games).
    @State private var playStartedInitially = false

    private enum Mode { case home, play, review, scan, savedGames }

    public init(style: GemmaLayoutStyle = .automatic) {}

    public var body: some View {
        NavigationStack {
            switch mode {
            case .home:
                HomeView(
                    onPlay: { playStartedInitially = false; mode = .play },
                    onReview: { mode = .review },
                    onScan: { mode = .scan },
                    onResume: { openSavedGame(withID: SavedGameStore.inProgressGameID()) },
                    onMyGames: { mode = .savedGames }
                )
            case .play:
                PlayContainerView(vm: play, onExit: { mode = .home }, startedInitially: playStartedInitially)
            case .review:
                reviewFlow
            case .scan:
                BoardScannerView(onStartGame: { fen, asWhite in
                    play.newGame(asWhite: asWhite, startFEN: fen)
                    playStartedInitially = true
                    mode = .play
                })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
            case .savedGames:
                SavedGamesView(onSelect: { saved in
                    play.load(saved)
                    playStartedInitially = true
                    mode = .play
                })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
            }
        }
        .gemmaChrome()
    }

    private func openSavedGame(withID id: UUID?) {
        guard let id, let saved = SavedGameStore.load(id: id) else { return }
        play.load(saved)
        playStartedInitially = true
        mode = .play
    }

    @ViewBuilder
    private var reviewFlow: some View {
        if review.session == nil {
            LoadView(vm: review)
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
        } else {
            ReviewScreen(vm: review, onNewGame: { review.session = nil })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) {
                    Button("Home") { review.session = nil; mode = .home }
                } }
        }
    }
}

/// Landing screen: choose Play or Review.
struct HomeView: View {
    var onPlay: () -> Void
    var onReview: () -> Void
    var onScan: () -> Void
    var onResume: () -> Void
    var onMyGames: () -> Void
    @State private var showLicenses = false
    @State private var showCoachSettings = false
    @State private var showBeginners = false
    /// "Scan a board" needs the managed coach (ChessCoach Pro) — a photo has
    /// to go over the network to be read, unlike everything else in the app.
    private var scanEnabled: Bool { ManagedCoachStore.loadBackendURL() != nil }
    /// Set whenever a game is mid-play when the app was last closed -- offers
    /// "Resume" instead of making the user start over from Home.
    private var inProgressGameID: UUID? { SavedGameStore.inProgressGameID() }
    private var hasSavedGames: Bool { !SavedGameStore.loadAll().isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            header
            Spacer()
            actions
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(isPresented: $showLicenses) { LicensesView() }
        .navigationDestination(isPresented: $showCoachSettings) { CoachSettingsView() }
        .navigationDestination(isPresented: $showBeginners) { BeginnersView() }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(GemmaTheme.accentGradient)
                .shadow(color: GemmaTheme.accent.opacity(0.55), radius: 20)
            VStack(spacing: 6) {
                Text("ChessCoach")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(0.3)
                Text("Play with a coach,\nor review one of your games.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if inProgressGameID != nil {
                Button(action: onResume) {
                    Label("Resume game", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button(action: onPlay) {
                Label(inProgressGameID != nil ? "Play a new game" : "Play a game",
                      systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(inProgressGameID != nil ? .white.opacity(0.16) : GemmaTheme.accent)

            Button(action: onReview) {
                Label("Review a game", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)

            // Everything below is a lower-emphasis, one-tap utility -- grouped into a
            // single glass card (the same language as Play mode's coach/hint cards)
            // instead of stacking near-identical outlined pills for each one.
            moreCard
                .padding(.top, 6)

            if hasSavedGames {
                Text("Games are saved on this device only")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)

            HStack(spacing: 16) {
                Button { showCoachSettings = true } label: {
                    Text("Coach Settings")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Button { showLicenses = true } label: {
                    Text("Open Source Licenses")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
    }

    /// "New to chess?" is always offered; "Scan a board" and "My Games" only when
    /// relevant (managed coach configured / at least one saved game).
    private var moreCard: some View {
        VStack(spacing: 0) {
            moreRow(icon: "graduationcap.fill", title: "New to chess?") { showBeginners = true }
            if scanEnabled {
                rowDivider
                moreRow(icon: "camera.viewfinder", title: "Scan a board", action: onScan)
            }
            if hasSavedGames {
                rowDivider
                moreRow(icon: "clock.arrow.circlepath", title: "My Games", action: onMyGames)
            }
        }
        .gemmaGlass(cornerRadius: 16)
    }

    private var rowDivider: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 46)
    }

    private func moreRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GemmaTheme.gold)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
