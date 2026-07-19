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

    @State private var puzzles = PuzzleViewModel()
    @State private var openingTrainer = OpeningTrainerViewModel()

    /// The active theme, shared with every screen via the environment --
    /// see Theme/ThemeStore.swift ("Living Themes").
    @State private var themeStore = ThemeStore()

    @State private var showOnboarding = !OnboardingStore.hasCompleted()
    @State private var showPaywall = false

    private enum Mode { case home, play, review, scan, savedGames, puzzles, openingTrainer, gameImport, lessons }

    public init(style: GemmaLayoutStyle = .automatic) {}

    public var body: some View {
        NavigationStack {
            switch mode {
            case .home:
                HomeView(
                    onPlay: { playStartedInitially = false; mode = .play },
                    onReview: { mode = .review },
                    onScan: { openScan() },
                    onResume: { openSavedGame(withID: SavedGameStore.inProgressGameID()) },
                    onMyGames: { mode = .savedGames },
                    onPuzzles: { mode = .puzzles },
                    onOpeningTrainer: { mode = .openingTrainer },
                    onGameImport: { mode = .gameImport },
                    onLessons: { mode = .lessons }
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
                .toolbar { settingsToolbarItem }
            case .savedGames:
                SavedGamesView(onSelect: { saved in
                    play.load(saved)
                    playStartedInitially = true
                    mode = .play
                })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
                .toolbar { settingsToolbarItem }
            case .puzzles:
                PuzzlesContainerView(vm: puzzles, onExit: { mode = .home })
            case .openingTrainer:
                OpeningTrainerContainerView(vm: openingTrainer, onExit: { mode = .home })
            case .gameImport:
                GameImportView()
                    .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
                    .toolbar { settingsToolbarItem }
            case .lessons:
                LessonsContainerView(onExit: { mode = .home })
            }
        }
        .environment(themeStore)
        .gemmaChrome(theme: themeStore.effective)
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onFinish: { showOnboarding = false })
                .environment(themeStore)
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onFinish: { showOnboarding = false })
                .environment(themeStore)
                .frame(minWidth: 480, minHeight: 640)
        }
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView().environment(themeStore) }
    }

    /// "Scan a board" needs the managed coach -- shows the paywall instead
    /// when this channel requires an entitlement the user doesn't have yet
    /// (see `BuildChannel.requiresProEntitlement`).
    private func openScan() {
        if BuildChannel.current.requiresProEntitlement, !ProEntitlementStore.shared.isProActive {
            showPaywall = true
        } else {
            mode = .scan
        }
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
                .toolbar { settingsToolbarItem }
        } else {
            ReviewScreen(vm: review, onNewGame: { review.session = nil })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) {
                    Button("Home") { review.session = nil; mode = .home }
                } }
                .toolbar { settingsToolbarItem }
        }
    }

    /// A trailing gear icon to the app-wide Settings hub -- added to every
    /// screen's toolbar so it's reachable from anywhere, not just Home.
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailingCompat) {
            NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
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
    var onPuzzles: () -> Void
    var onOpeningTrainer: () -> Void
    var onGameImport: () -> Void
    var onLessons: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @State private var showBeginners = false
    @State private var showSettings = false
    @State private var showMore = false
    @State private var emblemBreath = false
    /// "Scan a board" needs the managed coach (ChessCoach Pro) — a photo has
    /// to go over the network to be read, unlike everything else in the app.
    private var scanEnabled: Bool { ManagedCoachStore.loadBackendURL() != nil }
    /// Set whenever a game is mid-play when the app was last closed -- offers
    /// "Resume" instead of making the user start over from Home.
    private var inProgressGameID: UUID? { SavedGameStore.inProgressGameID() }
    private var hasSavedGames: Bool { !SavedGameStore.loadAll().isEmpty }
    private var theme: Theme { themeStore.effective }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 64)
                actions
                    .padding(.top, 28)
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topLeading) {
            menuButton
                .padding(.top, 12)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            settingsButton
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(isPresented: $showBeginners) { BeginnersView() }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showMore) { moreSheet }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                emblemBreath = true
            }
        }
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textColor.opacity(0.8))
                .frame(width: 34, height: 34)
        }
        .background(Circle().fill(theme.surfaceColor.opacity(0.8)))
        .buttonStyle(PressableStyle())
    }

    /// Opens the "More" sheet -- everything secondary that isn't worth a
    /// permanent row on Home (see `moreSheet`). Appearance now lives only in
    /// Settings, not as its own top-bar chip -- see this file's earlier
    /// header note on why Home was decluttered.
    private var menuButton: some View {
        Button { showMore = true } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textColor.opacity(0.8))
                .frame(width: 34, height: 34)
        }
        .background(Circle().fill(theme.surfaceColor.opacity(0.8)))
        .buttonStyle(PressableStyle())
    }

    private var header: some View {
        VStack(spacing: 12) {
            decoRule
            emblem
            VStack(spacing: 6) {
                Text("ChessCoach")
                    .font(theme.type.displayFont(size: 44))
                    .foregroundStyle(theme.textColor)
                    .tracking(theme.type.letterSpacing)
                    .textCase(theme.type.uppercased ? .uppercase : nil)
                Text(theme.name)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent2Color)
                Text("Play with a coach at your shoulder, or revisit the games that got away.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textColor.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 2)
            }
        }
    }

    /// A quiet flourish above the wordmark — two gradient lines + a diamond.
    private var decoRule: some View {
        HStack(spacing: 10) {
            decoLine
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(theme.accent2Color.opacity(0.9))
            decoLine
        }
        .frame(height: 1)
    }

    private var decoLine: some View {
        LinearGradient(
            colors: [theme.accent2Color.opacity(0), theme.accent2Color.opacity(0.9)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 50, height: 1)
    }

    private var emblem: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(theme.accentColor)
            .frame(width: 90, height: 90)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(theme.surfaceColor.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(theme.accentColor.opacity(0.45), lineWidth: 1)
                    )
            )
            .shadow(color: theme.accentColor.opacity(0.34), radius: 40)
            .scaleEffect(emblemBreath ? 1.04 : 1.0)
            .opacity(emblemBreath ? 1.0 : 0.85)
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
            .tint(inProgressGameID != nil ? theme.textColor.opacity(0.16) : theme.accentColor)
            .foregroundStyle(inProgressGameID != nil ? theme.textColor : theme.onAccentColor)

            // Review + Puzzles side by side instead of stacked full-width --
            // this pair reads as "secondary things you might also do," so a
            // 2-column row halves their vertical footprint without losing
            // legibility (this is what was forcing Home to scroll).
            HStack(spacing: 12) {
                secondaryActionCard(icon: "magnifyingglass", title: "Review a game", action: onReview)
                secondaryActionCard(icon: "puzzlepiece.fill", title: "Puzzles", action: onPuzzles)
            }

            // "New to chess?" is the one secondary action worth a permanent,
            // one-tap row on Home -- everything else (opening trainer, game
            // import, board scan, my games) lives behind the "More" menu
            // (top-leading icon) so adding new utilities never grows this
            // screen's scroll.
            beginnersCard
                .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
    }

    /// A compact, icon-over-label card for a secondary action -- half the
    /// width of a full-width button, used in a 2-column row.
    private func secondaryActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent2Color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(14)
        }
        .buttonStyle(PressableStyle())
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.textColor.opacity(0.16), lineWidth: 1)
        )
    }

    /// The one secondary action kept as a permanent Home row -- see `actions`'
    /// comment on why this one stays out of the "More" sheet.
    private var beginnersCard: some View {
        VStack(spacing: 0) {
            moreRow(icon: "graduationcap.fill", title: "New to chess?") { showBeginners = true }
        }
        // A plain themed card, NOT `.gemmaGlass()` -- Liquid Glass is meant for
        // floating/navigation chrome, never scrolling content (see GemmaTheme.swift's
        // header comment). Using real glass here, inside Home's ScrollView, produced
        // a visibly glitchy floating box as it tried to track scroll position.
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Everything secondary that isn't "New to chess?": opening trainer, game
    /// import, board scan (when configured), and My Games (when there's
    /// anything saved) -- reached via the top-leading menu icon instead of
    /// permanent Home rows, so adding future utilities never re-introduces
    /// Home's scroll.
    private var moreSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    moreRow(icon: "book.fill", title: "Lessons") {
                        showMore = false; onLessons()
                    }
                    rowDivider
                    moreRow(icon: "book.closed.fill", title: "Opening trainer") {
                        showMore = false; onOpeningTrainer()
                    }
                    rowDivider
                    moreRow(icon: "square.and.arrow.down", title: "Import a game") {
                        showMore = false; onGameImport()
                    }
                    if scanEnabled {
                        rowDivider
                        moreRow(icon: "camera.viewfinder", title: "Scan a board") {
                            showMore = false; onScan()
                        }
                    }
                    if hasSavedGames {
                        rowDivider
                        moreRow(icon: "clock.arrow.circlepath", title: "My Games") {
                            showMore = false; onMyGames()
                        }
                    }
                }
                .background(theme.cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)

                if hasSavedGames {
                    Text("Games are saved on this device only")
                        .font(.caption2)
                        .foregroundStyle(theme.textColor.opacity(0.4))
                        .padding(.bottom, 20)
                }
            }
            .background(theme.bgColor)
            .navigationTitle("More")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailingCompat) {
                    Button("Done") { showMore = false }
                }
            }
        }
        .environment(themeStore)
        .presentationDetents([.medium])
    }

    private var rowDivider: some View {
        Divider().overlay(theme.textColor.opacity(0.08)).padding(.leading, 46)
    }

    private func moreRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent2Color)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textColor.opacity(0.92))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.textColor.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
