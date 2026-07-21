//  PuzzlesView.swift
//  Puzzle mode UI: a theme list (download on demand, cached after) and a
//  compact solving view. Entirely free -- no coach involved.

import SwiftUI

/// Shows the theme list until one is started, then the solving session.
public struct PuzzlesContainerView: View {
    @Bindable var vm: PuzzleViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @Environment(BoardVisibility.self) private var boardVisibility
    @State private var showingRush = false
    @State private var streak = PuzzleStreakStore.currentStreak()
    @State private var pendingDeleteTheme: String?
    /// Per-band manual expand/collapse override -- defaults to expanded
    /// (see KTD-2: no search field on this screen, so no search-driven
    /// collapse rule to replicate from Opening Trainer).
    @State private var bandExpansion: [String: Bool] = [:]

    public init(vm: PuzzleViewModel, onExit: @escaping () -> Void) {
        self.vm = vm; self.onExit = onExit
    }

    public var body: some View {
        Group {
            if showingRush {
                PuzzleRushView(onExit: { showingRush = false })
            } else if vm.activeTheme != nil {
                PuzzleSessionView(vm: vm, onExit: { vm.endSession() })
            } else {
                themeList
            }
        }
        // Reports "a board is on screen" up to `GemmaRootView` so the global
        // tab bar can hide during an active session, without that view
        // needing to know Puzzles' own internal list-vs-session state.
        .onAppear { boardVisibility.visible = showingRush || vm.activeTheme != nil }
        .onChange(of: showingRush) { _, isRushing in boardVisibility.visible = isRushing || vm.activeTheme != nil }
        .onChange(of: vm.activeTheme) { _, theme in boardVisibility.visible = showingRush || theme != nil }
        .onDisappear { boardVisibility.visible = false }
    }

    private var theme: Theme { themeStore.effective }

    private var themeList: some View {
        ScrollView {
            VStack(spacing: 16) {
                blurb
                statsCard
                puzzleRushCard
                if let error = vm.catalogError, vm.catalog == nil {
                    errorCard(error)
                }
                if let catalog = vm.catalog {
                    ForEach(PuzzleRatingBand.allCases) { band in
                        let themesInBand = catalog.themes.filter { $0.ratingBand == band }
                        if !themesInBand.isEmpty {
                            bandGroup(band, themes: themesInBand)
                        }
                    }
                } else if vm.isLoadingCatalog {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Puzzles")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
            ToolbarItem(placement: .topBarTrailingCompat) {
                NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
            }
        }
        .task { if vm.catalog == nil { await vm.loadCatalog() } }
        .onAppear { streak = PuzzleStreakStore.currentStreak() }
        .confirmationDialog(
            "Delete this downloaded pack? You'll need to re-download it to solve more of its puzzles.",
            isPresented: Binding(
                get: { pendingDeleteTheme != nil },
                set: { if !$0 { pendingDeleteTheme = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let theme = pendingDeleteTheme { vm.deletePack(theme) }
                pendingDeleteTheme = nil
            }
        }
        .alert("Couldn't download", isPresented: .constant(vm.downloadError != nil && vm.downloadingTheme == nil)) {
            Button("OK") { vm.downloadError = nil }
        } message: {
            Text(vm.downloadError ?? "")
        }
    }

    private var blurb: some View {
        Text("Free — curated from the Lichess puzzle database (CC0). "
            + "Downloads once per theme, then works offline.")
            .font(.footnote)
            .foregroundStyle(theme.textColor.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Puzzle rating + (if any) daily streak, in one themed stats card
    /// (mirrors Home's stat-card visual language, see KTD-3).
    private var statsCard: some View {
        VStack(spacing: 12) {
            statRow(
                title: "Puzzle rating",
                subtitle: "Local only, puzzle-solving skill — not a rating of your overall play.",
                value: "\(vm.rating)",
                valueIcon: nil,
                valueColor: theme.accentColor
            )
            if streak > 0 {
                Divider().overlay(theme.cardBorderColor)
                statRow(
                    title: "Daily streak",
                    subtitle: "Solve at least one puzzle a day to keep it going.",
                    value: "\(streak)",
                    valueIcon: "flame.fill",
                    valueColor: theme.accent2Color
                )
            }
        }
        .padding(14)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statRow(title: String, subtitle: String, value: String, valueIcon: String?, valueColor: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text(subtitle).font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer()
            if let valueIcon {
                Label(value, systemImage: valueIcon)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(valueColor)
            } else {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(valueColor)
            }
        }
    }

    /// Full-width featured card above the rating bands (KTD-4) -- a mode
    /// (timed run across all themes), not a single theme, so it never lives
    /// inside a band's `DisclosureGroup`.
    private var puzzleRushCard: some View {
        Button {
            showingRush = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Puzzle Rush").font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                    Text("Timed run — solve as many as you can.")
                        .font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                }
                Spacer()
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

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.red)
            Button("Retry") { Task { await vm.loadCatalog() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// One rating band's `DisclosureGroup`, default-expanded, mirroring
    /// `OpeningTrainerView.familyGroup` (KTD-2) -- no search field on this
    /// screen, so there's no search-driven collapse rule to replicate.
    private func bandGroup(_ band: PuzzleRatingBand, themes: [PuzzleThemeInfo]) -> some View {
        DisclosureGroup(isExpanded: isExpandedBinding(for: band)) {
            VStack(spacing: 10) {
                ForEach(themes) { info in
                    themeCard(info)
                        // `packDeletionTick` isn't read by the card itself --
                        // this forces the card to rebuild after a delete so
                        // `isDownloaded`/`isBundled` (plain function calls,
                        // not observed properties) get re-evaluated.
                        .id("\(info.theme)-\(vm.packDeletionTick)")
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(band.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Spacer()
                Text("\(themes.count)")
                    .font(.caption).foregroundStyle(theme.textColor.opacity(0.5))
            }
        }
        .tint(theme.textColor)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isExpandedBinding(for band: PuzzleRatingBand) -> Binding<Bool> {
        Binding(
            get: { bandExpansion[band.rawValue] ?? true },
            set: { bandExpansion[band.rawValue] = $0 }
        )
    }

    /// A themed card per theme. Uses `.onTapGesture` (not a `Button`) for the
    /// whole-card tap target -- the "Delete" control inside is a real nested
    /// `Button`, and Button-inside-Button hit testing is unreliable in
    /// SwiftUI, exactly as in the pre-redesign `themeRow` this replaces.
    private func themeCard(_ info: PuzzleThemeInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text(ratingLabel(info))
                    .font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer()
            if vm.downloadingTheme == info.theme {
                ProgressView()
            } else if vm.isBundled(info.theme) {
                EmptyView()
            } else if vm.isDownloaded(info.theme) {
                Button(role: .destructive) {
                    pendingDeleteTheme = info.theme
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                Label("\(Int(info.sizeKB)) KB", systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(theme.accent2Color)
            }
        }
        .padding(12)
        .background(theme.surfaceColor.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !vm.isDownloading else { return }
            Task { await vm.downloadAndStart(info.theme) }
        }
    }

    private func ratingLabel(_ info: PuzzleThemeInfo) -> String {
        guard let lo = info.minRating, let hi = info.maxRating else { return "\(info.count) puzzles" }
        return "\(info.count) puzzles · rated \(lo)–\(hi)"
    }
}

/// The live puzzle-solving session.
struct PuzzleSessionView: View {
    @Bindable var vm: PuzzleViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }
    /// Set only when a solve pushes the daily streak to one of
    /// `StreakMilestones.values` -- surfaces a one-time share banner for
    /// that specific moment, not on every day's solve (plan U5).
    @State private var milestoneStreak: Int?

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                header
                board
                statusCard
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            if let milestoneStreak {
                StreakMilestoneBanner(streak: milestoneStreak) {
                    self.milestoneStreak = nil
                }
                .transition(AnyTransition.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onChange(of: vm.sessionSolvedCount) { old, new in
            guard new > old else { return }
            let streak = PuzzleStreakStore.recordSolve()
            if StreakMilestones.isMilestone(streak) {
                withAnimation(.easeOut(duration: 0.25)) { milestoneStreak = streak }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .gemmaGlassPill()
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(theme.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(PuzzleThemeInfo.displayName(for: vm.activeTheme ?? ""))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text("\(min(vm.puzzleIndex + 1, vm.sessionTotalCount))/\(vm.sessionTotalCount) · \(vm.sessionSolvedCount) solved this session")
                    .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var board: some View {
        if let puzzle = vm.currentPuzzle {
            ChessBoardView(
                fen: vm.fen,
                orientation: vm.orientation,
                arrows: [],
                lastMove: vm.lastMove,
                selectedSquare: vm.selected,
                legalDots: vm.legalDots,
                boardLight: theme.boardLightColor,
                boardDark: theme.boardDarkColor,
                highlightColor: theme.accent2Color,
                accentColor: theme.accentColor,
                onTapSquare: { vm.tap($0) }
            )
            .padding(.horizontal, 22)
            .id(puzzle.id)
        } else {
            completionCard
        }
    }

    private var completionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "party.popper.fill").font(.largeTitle).foregroundStyle(theme.accent2Color)
            Text("That's every puzzle in this pack for now.")
                .font(.headline).foregroundStyle(theme.textColor)
            Text("\(vm.sessionSolvedCount) solved this session — nice work.")
                .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
            Button("Back to themes", action: onExit)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private var statusCard: some View {
        if vm.currentPuzzle != nil {
            HStack(spacing: 8) {
                if let feedback = vm.feedback {
                    Image(systemName: icon(for: feedback))
                        .foregroundStyle(color(for: feedback))
                }
                Text(vm.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                Spacer()
                if vm.feedback == .solved {
                    Button("Next puzzle") { vm.nextPuzzle() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .gemmaGlassPill()
            .padding(.horizontal, 12)
        }
    }

    private func icon(for feedback: PuzzleFeedback) -> String {
        switch feedback {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .solved: return "star.fill"
        }
    }
    private func color(for feedback: PuzzleFeedback) -> Color {
        switch feedback {
        case .correct: return theme.accentColor
        case .incorrect: return .red
        case .solved: return theme.accent2Color
        }
    }
}

/// A one-time banner shown only when a solve pushes the daily streak to a
/// milestone value (plan U5) -- mirrors `PlayView.GameOverBanner`'s
/// share-card wiring pattern exactly (render via `ShareCardRenderer`,
/// present `ActivityShareSheet` on success, no-op on a nil render).
private struct StreakMilestoneBanner: View {
    let streak: Int
    var onDismiss: () -> Void

    @Environment(ThemeStore.self) private var themeStore
    @State private var appeared = false
    #if os(iOS)
    @State private var shareImage: StreakShareImageBox?
    #endif
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(theme.accent2Color)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
            Text("\(streak)-day streak!")
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.textColor)
            Text("Solved at least one puzzle every day for \(streak) days.")
                .font(.subheadline)
                .foregroundStyle(theme.textColor.opacity(0.75))
                .multilineTextAlignment(.center)
            #if os(iOS)
            Button {
                shareStreak()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.accentColor)
            .padding(.top, 6)
            #endif
            Text("Tap to dismiss")
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(0.4))
                .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: 300)
        .gemmaGlass(cornerRadius: 24)
        .shadow(color: theme.accent2Color.opacity(0.35), radius: 24)
        .onTapGesture(perform: onDismiss)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05)) {
                appeared = true
            }
        }
        #if os(iOS)
        .sheet(item: $shareImage) { box in
            ActivityShareSheet(items: [box.image])
        }
        #endif
    }

    #if os(iOS)
    /// Renders the streak share card and presents the system share sheet.
    /// If rendering fails for any reason, this is a safe no-op -- never
    /// presents a broken/empty share sheet.
    private func shareStreak() {
        let card = StreakShareCard(streak: streak).environment(themeStore)
        guard let image = ShareCardRenderer.render(card, size: StreakShareCard.cardSize) else {
            return
        }
        shareImage = StreakShareImageBox(image: image)
    }
    #endif
}

#if os(iOS)
/// `.sheet(item:)` needs `Identifiable`; `UIImage` isn't, so this wraps one
/// rendered streak share-card image per presentation.
private struct StreakShareImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif
