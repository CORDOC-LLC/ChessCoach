//  PuzzlesView.swift
//  Puzzle mode UI: a theme list (download on demand, cached after) and a
//  compact solving view. Entirely free -- no coach involved.

import SwiftUI

/// Shows the theme list until one is started, then the solving session.
public struct PuzzlesContainerView: View {
    @Bindable var vm: PuzzleViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @State private var showingRush = false
    @State private var streak = PuzzleStreakStore.currentStreak()

    public init(vm: PuzzleViewModel, onExit: @escaping () -> Void) {
        self.vm = vm; self.onExit = onExit
    }

    public var body: some View {
        if showingRush {
            PuzzleRushView(onExit: { showingRush = false })
        } else if vm.activeTheme != nil {
            PuzzleSessionView(vm: vm, onExit: { vm.endSession() })
        } else {
            themeList
        }
    }

    private var themeList: some View {
        List {
            Section {
                Text("Free — curated from the Lichess puzzle database (CC0). "
                    + "Downloads once per theme, then works offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Puzzle rating").font(.subheadline.weight(.semibold))
                        Text("Local only, puzzle-solving skill — not a rating of your overall play.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(vm.rating)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(themeStore.effective.accentColor)
                }
                if streak > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Daily streak").font(.subheadline.weight(.semibold))
                            Text("Solve at least one puzzle a day to keep it going.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(streak)", systemImage: "flame.fill")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(themeStore.effective.accent2Color)
                    }
                }
            }
            Section {
                Button {
                    showingRush = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Puzzle Rush").font(.subheadline.weight(.semibold))
                            Text("Timed run — solve as many as you can.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "timer").foregroundStyle(themeStore.effective.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
            if let error = vm.catalogError, vm.catalog == nil {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Retry") { Task { await vm.loadCatalog() } }
                }
            }
            if let catalog = vm.catalog {
                Section("Themes") {
                    ForEach(catalog.themes) { theme in
                        themeRow(theme)
                    }
                }
            } else if vm.isLoadingCatalog {
                Section {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Puzzles")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
            ToolbarItem(placement: .topBarTrailingCompat) {
                NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
            }
        }
        .task { if vm.catalog == nil { await vm.loadCatalog() } }
        .onAppear { streak = PuzzleStreakStore.currentStreak() }
    }

    private func themeRow(_ theme: PuzzleThemeInfo) -> some View {
        Button {
            Task { await vm.downloadAndStart(theme.theme) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.displayName).font(.subheadline.weight(.semibold))
                    Text(ratingLabel(theme))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if vm.downloadingTheme == theme.theme {
                    ProgressView()
                } else if vm.isDownloaded(theme.theme) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(themeStore.effective.accentColor)
                } else {
                    Label("\(Int(theme.sizeKB)) KB", systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(themeStore.effective.accent2Color)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(vm.isDownloading)
        .alert("Couldn't download", isPresented: .constant(vm.downloadError != nil && vm.downloadingTheme == nil)) {
            Button("OK") { vm.downloadError = nil }
        } message: {
            Text(vm.downloadError ?? "")
        }
    }

    private func ratingLabel(_ theme: PuzzleThemeInfo) -> String {
        guard let lo = theme.minRating, let hi = theme.maxRating else { return "\(theme.count) puzzles" }
        return "\(theme.count) puzzles · rated \(lo)–\(hi)"
    }
}

/// The live puzzle-solving session.
struct PuzzleSessionView: View {
    @Bindable var vm: PuzzleViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            header
            board
            statusCard
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onChange(of: vm.sessionSolvedCount) { old, new in
            if new > old { PuzzleStreakStore.recordSolve() }
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
