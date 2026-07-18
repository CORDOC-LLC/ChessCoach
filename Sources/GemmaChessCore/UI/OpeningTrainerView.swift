//  OpeningTrainerView.swift
//  Opening Trainer UI: search the local ECO book for a line, then a compact
//  drill session -- the board auto-plays the opponent's moves and prompts for
//  the user's, surfacing the correct continuation on a miss. Entirely free --
//  no coach involved.

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
