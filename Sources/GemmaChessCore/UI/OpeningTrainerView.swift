//  OpeningTrainerView.swift
//  Opening Trainer UI: search the local ECO book for a line, then a compact
//  drill session -- the board auto-plays the opponent's moves and prompts for
//  the user's, surfacing the correct continuation on a miss.
//
//  Three actions during a drill, two gating tiers (see OpeningTrainerViewModel's
//  header): "Hint" (free, reveals the next move) and "Moves" (free, the full
//  line's move list) are always available; "Coach" (Pro) asks why the move is
//  the book move, or a free-form follow-up question, and shows the paywall on
//  `vm.showPaywall` instead of a generic error when the caller isn't entitled.

import SwiftUI

/// Shows the search/browse list until a line is started, then the drill.
/// Lines are grouped into openable family sections (e.g. every "Queen's Pawn
/// Game: ..." variation together) rather than one long flat list -- see
/// `Openings.OpeningLine.family` / `OpeningTrainerViewModel.groupedResults`.
public struct OpeningTrainerContainerView: View {
    @Bindable var vm: OpeningTrainerViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.boardVisible) private var boardVisible
    /// Explicit expand/collapse choices the user has made, keyed by family --
    /// overrides the search-driven default (see `isExpandedBinding`).
    @State private var manualExpansion: [String: Bool] = [:]

    public init(vm: OpeningTrainerViewModel, onExit: @escaping () -> Void) {
        self.vm = vm; self.onExit = onExit
    }

    public var body: some View {
        Group {
            if vm.activeLine != nil {
                OpeningDrillView(vm: vm, onExit: { vm.endSession() })
            } else {
                lineList
            }
        }
        // See `PuzzlesContainerView`'s identical pattern -- reports the
        // drill's board visibility up to `GemmaRootView`.
        .onAppear { boardVisible.wrappedValue = vm.activeLine != nil }
        .onChange(of: vm.activeLine) { _, line in boardVisible.wrappedValue = line != nil }
        .onDisappear { boardVisible.wrappedValue = false }
    }

    private var lineList: some View {
        List {
            Section {
                Text("Free — drills the local ECO opening book. Correct moves raise a "
                    + "line's familiarity and push its next review further out; a miss "
                    + "resets it and shows the right continuation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Search by name or ECO code (e.g. \"Sicilian\", \"B20\")", text: Binding(
                    get: { vm.searchQuery },
                    set: { vm.search($0) }
                ))
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
            }
            ForEach(vm.groupedResults) { group in
                familyGroup(group)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Opening Trainer")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
        }
    }

    private func familyGroup(_ group: OpeningFamilyGroup) -> some View {
        DisclosureGroup(isExpanded: isExpandedBinding(for: group.id)) {
            ForEach(group.lines) { line in
                lineRow(line)
            }
        } label: {
            HStack {
                Text(group.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.lines.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Actively searching (a narrowed, small result set) expands every
    /// matching family by default, since the user is looking for something
    /// specific; browsing the full book (empty query) keeps families
    /// collapsed by default so the list isn't hundreds of rows deep. Once
    /// the user explicitly toggles a family, that choice wins from then on.
    private func isExpandedBinding(for family: String) -> Binding<Bool> {
        Binding(
            get: {
                manualExpansion[family]
                    ?? !vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            set: { manualExpansion[family] = $0 }
        )
    }

    private func lineRow(_ line: Openings.OpeningLine) -> some View {
        Button {
            vm.start(line: line, userIsWhite: vm.userIsWhite)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.variationLabel ?? "Main line").font(.subheadline.weight(.semibold))
                    Text("\(line.eco) · \(line.sanMoves.count) moves")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let familiarity = OpeningTrainerStore.familiarity(for: line.id, defaults: .standard) {
                    if familiarity.isLearned {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(themeStore.effective.accentColor)
                    } else {
                        Text("Lvl \(familiarity.level)")
                            .font(.caption2).foregroundStyle(themeStore.effective.accent2Color)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The live drill session for a single opening line.
///
/// Hint/Moves/Coach live in an inline panel BELOW the board (never a sheet
/// covering it) so the board stays visible while reading -- the panel itself
/// scrolls internally when its content runs long. While the Moves panel is
/// selected, the board shows a step-by-step preview (an arrow for the move
/// at `vm.previewIndex`, stepped with Back/Next) instead of the live drill
/// position -- purely a read-only walkthrough, so tapping the board is
/// disabled during preview and resumes the real drill once another panel
/// (or none) is selected.
struct OpeningDrillView: View {
    @Bindable var vm: OpeningTrainerViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @State private var selectedPanel: Panel? = nil
    @State private var questionText = ""
    private var theme: Theme { themeStore.effective }

    private enum Panel: String, CaseIterable, Identifiable {
        case hint = "Hint", moves = "Moves", coach = "Coach"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .hint: return "lightbulb.fill"
            case .moves: return "list.bullet"
            case .coach: return "bubble.left.fill"
            }
        }
    }

    /// Only the Moves panel puts the board into a read-only step-through
    /// preview -- Hint and Coach don't change what the board shows.
    private var isPreviewingMoves: Bool { selectedPanel == .moves }

    var body: some View {
        VStack(spacing: 10) {
            header
            board
            statusCard
            panelPicker
            panelContent
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
    }

    private var panelPicker: some View {
        HStack(spacing: 10) {
            ForEach(Panel.allCases) { panel in
                panelButton(panel)
            }
        }
        .padding(.horizontal, 14)
    }

    private func panelButton(_ panel: Panel) -> some View {
        let isSelected = selectedPanel == panel
        return Button {
            if isSelected {
                selectedPanel = nil
            } else {
                selectedPanel = panel
                if panel == .hint { vm.showHint() }
                if panel == .moves { vm.resetPreviewToCurrentMove() }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: panel.icon).font(.subheadline.weight(.semibold))
                Text(panel.rawValue).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(isSelected ? theme.onAccentColor : theme.textColor.opacity(0.85))
        .background(isSelected ? theme.accentColor : theme.cardBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.clear : theme.cardBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The scrollable box under the board/actions -- bounded height so the
    /// board above it always stays fully visible; content inside scrolls
    /// instead of pushing the board off-screen.
    @ViewBuilder
    private var panelContent: some View {
        if let selectedPanel {
            ScrollView {
                switch selectedPanel {
                case .hint: hintPanel
                case .moves: movesPanel
                case .coach: coachPanel
                }
            }
            .frame(maxHeight: 260)
            .padding(.horizontal, 14)
        }
    }

    private var hintPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = vm.revealedHintSAN {
                Text("Next move: \(hint)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent2Color)
            } else {
                Text("No more moves to hint in this line.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var movesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { vm.stepPreviewBackward() } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                .disabled(!vm.canStepPreviewBackward)
                Button { vm.stepPreviewForward() } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
                .disabled(!vm.canStepPreviewForward)
                Spacer()
                Button("Jump to current move") { vm.resetPreviewToCurrentMove() }
                    .font(.caption)
            }
            .foregroundStyle(theme.accentColor)

            if let line = vm.activeLine {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(line.sanMoves.enumerated()), id: \.offset) { index, san in
                        moveRow(index: index, san: san)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func moveRow(index: Int, san: String) -> some View {
        let isPreviewed = index == vm.previewIndex
        return Button {
            vm.jumpPreview(to: index)
        } label: {
            HStack {
                Text("\(index / 2 + 1)\(index % 2 == 0 ? "." : "...")")
                    .foregroundStyle(.secondary)
                Text(san).font(.body.weight(.medium))
                Spacer()
                if index < vm.moveCursorForDisplay {
                    Image(systemName: "checkmark").foregroundStyle(theme.accentColor)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isPreviewed ? theme.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textColor)
    }

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Task { await vm.askWhyCurrentMove() }
            } label: {
                Label("Why this move?", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isAskingCoach)

            HStack {
                TextField("Ask a question about this line...", text: $questionText)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                Button("Ask") {
                    let text = questionText
                    questionText = ""
                    Task { await vm.askQuestion(text) }
                }
                .disabled(vm.isAskingCoach || questionText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if vm.isAskingCoach {
                ProgressView().frame(maxWidth: .infinity)
            } else if let answer = vm.coachAnswer {
                Text(answer).font(.subheadline).foregroundStyle(theme.textColor)
            } else if let error = vm.coachError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text(vm.activeLine?.name ?? "")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text(vm.activeLine?.eco ?? "")
                    .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var board: some View {
        ChessBoardView(
            fen: isPreviewingMoves ? vm.previewFEN : vm.fen,
            orientation: vm.orientation,
            arrows: previewArrows,
            lastMove: isPreviewingMoves ? nil : vm.lastMove,
            selectedSquare: isPreviewingMoves ? nil : vm.selected,
            legalDots: isPreviewingMoves ? [] : vm.legalDots,
            boardLight: theme.boardLightColor,
            boardDark: theme.boardDarkColor,
            highlightColor: theme.accent2Color,
            accentColor: theme.accentColor,
            // Read-only while previewing -- stepping through moves never
            // disturbs the real drill's in-progress attempt.
            onTapSquare: { square in if !isPreviewingMoves { vm.tap(square) } }
        )
        .padding(.horizontal, 22)
    }

    private var previewArrows: [BoardArrow] {
        guard isPreviewingMoves, let uci = vm.previewMoveUCI,
              let arrow = BoardArrow(uci: uci, color: theme.accentColor, thick: true)
        else { return [] }
        return [arrow]
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 8) {
            if let feedback = vm.feedback {
                Image(systemName: icon(for: feedback))
                    .foregroundStyle(color(for: feedback))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                if let level = vm.familiarity?.level {
                    Text("Familiarity level \(level)")
                        .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
                }
            }
            Spacer()
            if vm.feedback == .lineComplete {
                Button("Back to lines") { onExit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .gemmaGlassPill()
        .padding(.horizontal, 12)
    }

    private func icon(for feedback: OpeningTrainerFeedback) -> String {
        switch feedback {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .lineComplete: return "star.fill"
        }
    }
    private func color(for feedback: OpeningTrainerFeedback) -> Color {
        switch feedback {
        case .correct: return theme.accentColor
        case .incorrect: return .red
        case .lineComplete: return theme.accent2Color
        }
    }
}
