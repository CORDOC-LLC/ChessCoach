//  ReviewScreen.swift
//  The review surface: board + eval bar + win graph, a move scrubber, the mistakes
//  list, a verdict box for the current move, and the coach panel. Reads everything
//  off the @Observable ReviewViewModel.

import SwiftUI

public struct ReviewScreen: View {
    @Bindable var vm: ReviewViewModel
    /// Called when the user wants to leave the review (e.g. analyse another game).
    public var onNewGame: (() -> Void)?

    public init(vm: ReviewViewModel, onNewGame: (() -> Void)? = nil) {
        self.vm = vm
        self.onNewGame = onNewGame
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accuracyHeader
                boardRow
                scrubber
                if !(vm.session?.timeline.isEmpty ?? true) {
                    WinGraphView(values: vm.winValues, currentIndex: vm.currentNode) { vm.goto(node: $0) }
                }
                verdictBox
                mistakesList
                CoachChatView(vm: vm)
            }
            .padding()
        }
        .navigationTitle(navTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let onNewGame {
                ToolbarItem {
                    Button("New game", action: onNewGame)
                }
            }
        }
    }

    private var navTitle: String {
        guard let s = vm.session else { return "Review" }
        let opening = s.resolveOpening()
        return opening.isEmpty ? "\(s.headers["White"] ?? "?") vs \(s.headers["Black"] ?? "?")" : opening
    }

    private var accuracyHeader: some View {
        HStack(spacing: 16) {
            accuracyChip(label: "White", value: vm.session?.accuracyWhite)
            accuracyChip(label: "Black", value: vm.session?.accuracyBlack)
            Spacer()
            if let n = vm.session?.mistakes.count {
                Text("\(n) mistake\(n == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func accuracyChip(label: String, value: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—").font(.headline)
        }
    }

    private var boardRow: some View {
        HStack(alignment: .top, spacing: 8) {
            EvalBarView(winWhite: vm.winWhiteCurrent, whiteAtBottom: vm.orientationIsWhite)
            ChessBoardView(
                fen: vm.currentFEN ?? "8/8/8/8/8/8/8/8 w - - 0 1",
                orientation: vm.orientation,
                arrows: vm.boardArrows,
                lastMove: vm.lastMoveSquares)
        }
        .frame(maxHeight: 420)
    }

    private var scrubber: some View {
        VStack(spacing: 8) {
            if vm.nodeCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(vm.currentNode) },
                        set: { vm.goto(node: Int($0.rounded())) }),
                    in: 0...Double(max(vm.nodeCount - 1, 1)),
                    step: 1)
            }
            HStack {
                Button { vm.prev() } label: { Image(systemName: "chevron.left") }
                    .disabled(vm.currentNode <= 0)
                Text("Move \(vm.currentNode) / \(max(vm.nodeCount - 1, 0))")
                    .font(.footnote).monospacedDigit()
                    .frame(minWidth: 120)
                Button { vm.next() } label: { Image(systemName: "chevron.right") }
                    .disabled(vm.currentNode >= vm.nodeCount - 1)
                Spacer()
                Button { vm.flip() } label: { Label("Flip", systemImage: "arrow.up.arrow.down") }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var verdictBox: some View {
        if let v = vm.verdict {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(v.moveSAN).font(.headline)
                    Text(v.classification.capitalized)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(color(for: v.classification).opacity(0.2), in: Capsule())
                        .foregroundStyle(color(for: v.classification))
                    Spacer()
                    Text("win \(fmt(v.winBefore))% → \(fmt(v.winAfter))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if v.bestMoveSAN != v.moveSAN && !v.bestMoveSAN.isEmpty {
                    Text("Better: \(v.bestMoveSAN)").font(.subheadline)
                }
                if !v.comment.isEmpty {
                    Text(v.comment).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var mistakesList: some View {
        if let mistakes = vm.session?.mistakes, !mistakes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mistakes").font(.headline)
                ForEach(Array(mistakes.enumerated()), id: \.offset) { index, m in
                    Button { vm.gotoMistake(index: index) } label: {
                        HStack {
                            Text("\(m.moveNumber)\(m.color == "white" ? "." : "...") \(m.moveSAN)")
                                .font(.subheadline).fontWeight(.medium)
                            Text(m.classification.capitalized)
                                .font(.caption).foregroundStyle(color(for: m.classification))
                            Spacer()
                            Text("-\(fmt(m.winSwing))%").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func color(for classification: String) -> Color {
        switch classification {
        case "blunder": return .red
        case "mistake": return .orange
        case "inaccuracy": return .yellow
        case "best", "good", "excellent": return .green
        default: return .secondary
        }
    }

    private func fmt(_ x: Double) -> String {
        x == x.rounded() ? String(format: "%.0f", x) : String(format: "%.1f", x)
    }
}
