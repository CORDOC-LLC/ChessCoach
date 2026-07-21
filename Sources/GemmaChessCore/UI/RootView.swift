//  RootView.swift
//  The shared app entry. Both app shells embed `GemmaRootView()`. A Home screen
//  routes to Play mode (new game vs the engine, with live coaching) or Review mode
//  (paste/import a game and study it). Each mode runs in the navigation stack.

import SwiftUI

/// Retained for source compatibility with the app shells; the root is stack-based.
public enum GemmaLayoutStyle: Sendable {
    case automatic, column, split
}

/// Lets a screen whose board/non-board sub-state is private (Puzzles'
/// theme-list-vs-session, Lessons' stage-list-vs-practice, Opening Trainer's
/// line-list-vs-drill) report "a chessboard is on screen right now" up to
/// `GemmaRootView` without threading a callback through every intermediate
/// view. Play and Review don't need this -- `GemmaRootView` already owns
/// their board-vs-not state directly (`mode == .play`, `review.session`).
///
/// DELIBERATELY an `@Observable` box injected via `.environment(_:)`, NOT a
/// `Binding` stored in a custom `EnvironmentValues` key. The first version of
/// this used a Binding, and that hung the whole app: a fresh Binding value
/// (new closure identities) was produced on every root body evaluation, and
/// since Binding isn't Equatable, SwiftUI's environment diffing saw "changed"
/// on every commit and rebuilt the entire view tree -- with the standing
/// board/emblem animations committing every frame, that meant a full-app
/// rebuild per frame, a pinned main thread, and iOS's scene-create watchdog
/// killing the app at launch (0x8BADF00D, confirmed via device crash logs and
/// a simulator bisect). A class instance has stable identity, so the
/// environment never reads as changed; observation triggers re-render only
/// when `visible` actually flips.
@MainActor
@Observable
final class BoardVisibility {
    var visible = false
}

public struct GemmaRootView: View {
    @State private var review = ReviewViewModel()
    @State private var play = PlayViewModel()
    @State private var mode: Mode = .home
    /// Whether a chessboard is currently on screen inside Puzzles/Lessons/
    /// Opening Trainer's own internal session state -- see `BoardVisibility`
    /// above. Play and Review don't set this; their board-vs-not state is
    /// computed directly from `mode`/`review.session` in `isBoardOnScreen`.
    @State private var boardVisibility = BoardVisibility()
    /// Whether the bottom tab bar shows even while a chessboard is on screen
    /// (Play, a Puzzle/Lesson/Opening Trainer session, or Review's analysis
    /// screen) -- everywhere else it's always shown regardless of this.
    /// Defaults OFF: the tab bar auto-hides whenever a board is visible,
    /// freeing that height for the move list/coach card, and a Settings
    /// toggle lets a player override that.
    ///
    /// DELIBERATELY a `UserDefaults`-mirroring `@State`, NOT `@AppStorage`.
    /// On iOS 26, an `@AppStorage` property read inside THIS view's body
    /// re-invalidated the root on every animation frame (verified by a
    /// simulator A/B: identical body with `@AppStorage` pins the CPU at
    /// 100% and the first frame never commits -- iOS's scene-create
    /// watchdog then kills the app at launch, 0x8BADF00D; the same body
    /// with `@State` idles at ~4%). The previous condition (`mode != .play
    /// || showTabBarDuringPlay`) only dodged this by accident: `||`
    /// short-circuited, so the `@AppStorage` was never actually read
    /// outside Play mode. The `.onReceive` below keeps this in sync with
    /// the `SettingsView` toggle (which still writes the same
    /// `UserDefaults` key) -- state is only mutated when the value truly
    /// changed, so the notification handler can never re-render-loop.
    @State private var showTabBarWithBoard =
        UserDefaults.standard.bool(forKey: GemmaRootView.showTabBarWithBoardKey)

    /// The `UserDefaults` key shared with `SettingsView`'s toggle.
    static let showTabBarWithBoardKey = "play.showTabBarWithBoard"
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

    fileprivate enum Mode { case home, play, review, scan, puzzles, openingTrainer, gameImport, lessons, weaknessReport }

    public init(style: GemmaLayoutStyle = .automatic) {}

    public var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                modeContent
            }
            if showTabBarWithBoard || !isBoardOnScreen {
                GlobalTabBar(activeTab: HomeTab(mode: mode), onSelect: select(_:))
            }
        }
        .environment(boardVisibility)
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
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let value = UserDefaults.standard.bool(forKey: Self.showTabBarWithBoardKey)
            if value != showTabBarWithBoard { showTabBarWithBoard = value }
        }
    }

    /// The active screen, type-erased per case. AnyView here is deliberate and
    /// load-bearing, not laziness: with all nine cases composed as one
    /// `_ConditionalContent` sum type (each case carrying its own toolbars and
    /// full screen hierarchy), the root view's generic type became so enormous
    /// that SwiftUI's FIRST render spent 20+ seconds of CPU instantiating its
    /// metadata and diffing it -- iOS's scene-create watchdog then killed the
    /// app (0x8BADF00D, verified from on-device .ips crash logs; the crashes
    /// began the exact evening this switch moved inside the VStack+tab-bar
    /// wrapper). Erasing each case caps the composed type at AnyView, and
    /// costs nothing real: the cases are entirely different screens, so
    /// cross-case diffing was never useful.
    private var modeContent: AnyView {
        switch mode {
        case .home:
            AnyView(HomeView(
                onPlay: { playStartedInitially = false; mode = .play },
                onReview: { mode = .review },
                onScan: { openScan() },
                onResume: { openSavedGame(withID: SavedGameStore.inProgressGameID()) },
                onSelectSavedGame: { saved in
                    play.load(saved)
                    playStartedInitially = true
                    mode = .play
                },
                onPuzzles: { mode = .puzzles },
                onOpeningTrainer: { mode = .openingTrainer },
                onGameImport: { mode = .gameImport },
                onLessons: { mode = .lessons },
                onWeaknessReport: { mode = .weaknessReport }
            ))
        case .play:
            AnyView(PlayContainerView(vm: play, onExit: { mode = .home }, startedInitially: playStartedInitially))
        case .review:
            AnyView(reviewFlow)
        case .scan:
            AnyView(BoardScannerView(onStartGame: { fen, asWhite in
                play.newGame(asWhite: asWhite, startFEN: fen)
                playStartedInitially = true
                mode = .play
            })
            .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
            .toolbar { settingsToolbarItem })
        case .puzzles:
            AnyView(PuzzlesContainerView(vm: puzzles, onExit: { mode = .home }))
        case .openingTrainer:
            AnyView(OpeningTrainerContainerView(vm: openingTrainer, onExit: { mode = .home }))
        case .gameImport:
            AnyView(GameImportView()
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
                .toolbar { settingsToolbarItem })
        case .lessons:
            AnyView(LessonsContainerView(onExit: { mode = .home }))
        case .weaknessReport:
            AnyView(WeaknessReportView(
                onExit: { mode = .home },
                onOpenLesson: { _ in mode = .lessons },
                onOpenPuzzleTheme: { _ in mode = .puzzles }
            )
            .toolbar { settingsToolbarItem })
        }
    }

    /// Whether a chessboard is on screen right now -- Play always is; Review
    /// is once a session has loaded; Puzzles/Lessons/Opening Trainer report
    /// their own internal session state via the shared `BoardVisibility` box
    /// (injected through the environment, since their board-vs-list state is
    /// private to those views). The tab bar hides whenever this is true,
    /// unless `showTabBarWithBoard` overrides it.
    private var isBoardOnScreen: Bool {
        switch mode {
        case .play: true
        case .review: review.session != nil
        case .puzzles, .lessons, .openingTrainer: boardVisibility.visible
        default: false
        }
    }

    /// Handles a tap on any `GlobalTabBar` item, from any screen -- tapping
    /// the tab matching the screen already on is a no-op (SwiftUI just
    /// re-renders the same case), tapping any other tab navigates there.
    private func select(_ tab: HomeTab) {
        switch tab {
        case .home: mode = .home
        case .lessons: mode = .lessons
        case .openings: mode = .openingTrainer
        case .puzzles: mode = .puzzles
        }
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
    /// `onSelectSavedGame` lets Settings' "My Games" row (see SettingsView.swift)
    /// resume a game -- Settings pops itself (and the nested My Games push)
    /// via its own `dismiss()` before this fires, so the mode change below is
    /// immediately visible instead of hiding under two still-open pushes.
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailingCompat) {
            NavigationLink(destination: SettingsView(onSelectSavedGame: { saved in
                play.load(saved)
                playStartedInitially = true
                mode = .play
            })) { Image(systemName: "gearshape") }
        }
    }
}

/// The four top-level sections reachable from the global bottom tab bar
/// (`GlobalTabBar`, present on every screen except while a chessboard is on
/// screen -- see `GemmaRootView.isBoardOnScreen`/`showTabBarWithBoard`).
/// Selecting a tab navigates to the matching screen; screens with no
/// matching tab (Play, Review, Scan, Game Import, the Weakness Report) fall
/// back to highlighting Home, since none of the four items represents them.
enum HomeTab: String, CaseIterable {
    case home, lessons, openings, puzzles

    /// Maps `GemmaRootView`'s internal `Mode` to the tab that should read as
    /// "active" -- `nil`/unmatched modes fall back to `.home`.
    fileprivate init(mode: GemmaRootView.Mode) {
        switch mode {
        case .lessons, .weaknessReport: self = .lessons
        case .openingTrainer: self = .openings
        case .puzzles: self = .puzzles
        default: self = .home
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .lessons: "Lessons"
        case .openings: "Openings"
        case .puzzles: "Puzzles"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .lessons: "book.fill"
        case .openings: "book.closed.fill"
        case .puzzles: "puzzlepiece.fill"
        }
    }
}

/// The global bottom tab bar, present on every screen except while a
/// chessboard is actually on screen (Play, a Puzzle/Lesson/Opening Trainer
/// session, or Review's analysis view -- see `GemmaRootView.isBoardOnScreen`),
/// where it hides by default to give that space back to the move list/coach
/// card (overridable via `showTabBarWithBoard`). Promoted from Home-only
/// (this file's earlier design) after the tab bar shipped and felt
/// inconsistent everywhere else. Not a persistent `TabView`: it's a plain
/// navigation-trigger row that sits below whichever screen is showing,
/// entirely independent of that screen's own `NavigationStack`.
struct GlobalTabBar: View {
    var activeTab: HomeTab
    var onSelect: (HomeTab) -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                tabBarItem(tab)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            theme.cardBackgroundColor
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.cardBorderColor).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabBarItem(_ tab: HomeTab) -> some View {
        Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tab == activeTab ? theme.accentColor : theme.textColor.opacity(0.6))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Landing screen: choose Play or Review.
struct HomeView: View {
    var onPlay: () -> Void
    var onReview: () -> Void
    var onScan: () -> Void
    var onResume: () -> Void
    var onSelectSavedGame: (SavedGame) -> Void
    var onPuzzles: () -> Void
    var onOpeningTrainer: () -> Void
    var onGameImport: () -> Void
    var onLessons: () -> Void
    var onWeaknessReport: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @State private var showBeginners = false
    @State private var showSettings = false
    @State private var emblemBreath = false
    @State private var weaknessReportTeaser: String?
    /// "Scan a board" needs the managed coach (ChessCoach Pro) — a photo has
    /// to go over the network to be read, unlike everything else in the app.
    private var scanEnabled: Bool { ManagedCoachStore.loadBackendURL() != nil }
    /// Set whenever a game is mid-play when the app was last closed -- offers
    /// "Resume" instead of making the user start over from Home.
    private var inProgressGameID: UUID? { SavedGameStore.inProgressGameID() }
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
        .overlay(alignment: .topTrailing) {
            settingsButton
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(isPresented: $showBeginners) { BeginnersView() }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(onSelectSavedGame: onSelectSavedGame)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                emblemBreath = true
            }
            // Local-only, no network regardless of Pro status (R6) -- safe to
            // compute on every Home appearance. Dispatched off the main actor:
            // this reads and decodes the full history file from disk, which
            // was blocking the Home transition (worse as history grows).
            Task.detached(priority: .utility) {
                let teaser = CoachingProfileBuilder.topTeaserMotif(
                    CoachingProfileBuilder.buildProfile(playerID: "me", store: HistoryStore()))
                await MainActor.run { weaknessReportTeaser = teaser }
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
            // Shadow radius kept modest (was 40): the breathing animation
            // below re-composites this view every frame while Home is
            // visible, and a huge blur radius made that a standing offscreen
            // render pass. 14pt reads nearly identically on a 90pt emblem.
            .shadow(color: theme.accentColor.opacity(0.4), radius: 14)
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

            // Review / Scan / Import side by side -- Lessons, Opening Trainer,
            // and Puzzles moved to the bottom tab bar (see `HomeTab`), which
            // freed this row for the two utilities the tab bar can't hold:
            // scanning a physical board and importing a game.
            HStack(spacing: 12) {
                secondaryActionCard(icon: "magnifyingglass", title: "Review", action: onReview)
                if scanEnabled {
                    secondaryActionCard(icon: "camera.viewfinder", title: "Scan", action: onScan)
                }
                secondaryActionCard(icon: "square.and.arrow.down", title: "Import", action: onGameImport)
            }

            // "New to chess?" is the one secondary action worth a permanent,
            // full-width row on Home.
            beginnersCard
                .padding(.top, 6)

            // Weakness Report teaser (plan U7/R2) -- only appears once there's
            // real local data to show (never an empty/broken card for a
            // brand-new player).
            if let motif = weaknessReportTeaser {
                weaknessReportCard(motif)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
    }

    /// A compact, icon-over-label card for a secondary action -- half the
    /// width of a full-width button, used in a 2-column row. Titles here are
    /// deliberately short single words ("Review", "Scan", "Import") so they
    /// always render on one line -- a previous version used longer titles
    /// ("Review a game", "Scan a board") that wrapped to two lines on
    /// narrower screens while "Import" stayed on one, making that card
    /// visibly shorter than its neighbors in the same row.
    private func secondaryActionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent2Color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
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

    /// The one full-width secondary action on Home.
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

    /// A themed teaser card pointing at the Weakness Report (plan U7) -- the
    /// motif name itself is already-free data (R8), the coach's narrative
    /// explanation is what's actually locked, on the report screen itself.
    private func weaknessReportCard(_ motif: String) -> some View {
        Button(action: onWeaknessReport) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent2Color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your coach has something to tell you")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                    Text("Most common miss: \(motif)")
                        .font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.textColor.opacity(0.3))
            }
            .padding(14)
        }
        .buttonStyle(PressableStyle())
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
