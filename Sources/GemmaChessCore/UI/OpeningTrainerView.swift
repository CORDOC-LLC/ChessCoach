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
public struct OpeningTrainerContainerView: View {
    @Bindable var vm: OpeningTrainerViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore

    public init(vm: OpeningTrainerViewModel, onExit: @escaping () -> Void) {
        self.vm = vm; self.onExit = onExit
    }

    public var body: some View {
        if vm.activeLine != nil {
            OpeningDrillView(vm: vm, onExit: { vm.endSession() })
        } else {
            lineList
        }
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
            Section("Lines") {
                ForEach(vm.results.prefix(200)) { line in
                    lineRow(line)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Opening Trainer")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
        }
    }

    private func lineRow(_ line: Openings.OpeningLine) -> some View {
        Button {
            vm.start(line: line, userIsWhite: vm.userIsWhite)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name).font(.subheadline.weight(.semibold))
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
struct OpeningDrillView: View {
    @Bindable var vm: OpeningTrainerViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    @State private var showMoveList = false
    @State private var showCoach = false
    @State private var questionText = ""
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            header
            board
            statusCard
            actionsRow
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showMoveList) { moveListSheet }
        .sheet(isPresented: $showCoach) { coachSheet }
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
    }

    /// Hint and Moves are free; Coach is Pro (see this file's header).
    @ViewBuilder
    private var actionsRow: some View {
        HStack(spacing: 10) {
            actionButton(icon: "lightbulb.fill", title: "Hint") { vm.showHint() }
            actionButton(icon: "list.bullet", title: "Moves") { showMoveList = true }
            actionButton(icon: "bubble.left.fill", title: "Coach") { showCoach = true }
        }
        .padding(.horizontal, 14)

        if let hint = vm.revealedHintSAN {
            Text("Next move: \(hint)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent2Color)
                .padding(.horizontal, 14)
        }
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.textColor.opacity(0.85))
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var moveListSheet: some View {
        NavigationStack {
            List {
                if let line = vm.activeLine {
                    ForEach(Array(line.sanMoves.enumerated()), id: \.offset) { index, san in
                        HStack {
                            Text("\(index / 2 + 1)\(index % 2 == 0 ? "." : "...")")
                                .foregroundStyle(.secondary)
                            Text(san).font(.body.weight(.medium))
                            Spacer()
                            if index < vm.moveCursorForDisplay {
                                Image(systemName: "checkmark").foregroundStyle(theme.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(vm.activeLine?.name ?? "Moves")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailingCompat) { Button("Done") { showMoveList = false } }
            }
        }
        .environment(themeStore)
    }

    private var coachSheet: some View {
        NavigationStack {
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
                Spacer()
            }
            .padding(20)
            .navigationTitle("Coach")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailingCompat) { Button("Done") { showCoach = false } }
            }
        }
        .environment(themeStore)
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
