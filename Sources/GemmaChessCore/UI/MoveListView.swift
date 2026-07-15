//  MoveListView.swift
//  A compact, scrollable two-column move list (move number · White · Black) in SAN.
//  Tapping a ply sets the view-model's viewing cursor so the board shows that past
//  position with played/best arrows. Floating-layer glass card; the board stays content.

import SwiftUI

/// One numbered row of the move list: a move number and the two plies (SAN).
struct MoveRow: Equatable {
    let number: Int
    let white: String
    let black: String?
}

/// Pure, testable shaping of the SAN move list — pairing plies into numbered rows
/// and resolving which ply is "current".
enum MoveListFormatter {
    /// Pair plies into numbered rows (White, then optional Black).
    static func rows(from san: [String]) -> [MoveRow] {
        var rows: [MoveRow] = []
        var i = 0, number = 1
        while i < san.count {
            rows.append(MoveRow(
                number: number,
                white: san[i],
                black: (i + 1 < san.count) ? san[i + 1] : nil
            ))
            i += 2; number += 1
        }
        return rows
    }

    /// The 0-based ply index highlighted as current: the viewing cursor if set,
    /// else the latest ply, or nil for an empty game.
    static func activePly(viewingPly: Int?, moveCount: Int) -> Int? {
        if let v = viewingPly { return v }
        return moveCount == 0 ? nil : moveCount - 1
    }
}

struct MoveListView: View {
    @Bindable var vm: PlayViewModel
    @Environment(ThemeStore.self) private var themeStore

    /// 0-based index of the ply currently highlighted (viewing cursor, else the live ply).
    private var activePly: Int? {
        MoveListFormatter.activePly(viewingPly: vm.viewingPly, moveCount: vm.sanMoves.count)
    }

    private var rowCount: Int { (vm.sanMoves.count + 1) / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet").foregroundStyle(themeStore.effective.accentColor)
                Text("Moves").font(.subheadline.weight(.semibold)).foregroundStyle(themeStore.effective.textColor)
                Spacer()
                if vm.isViewingHistory {
                    Button { vm.returnToLive() } label: {
                        Label("Return to game", systemImage: "arrow.uturn.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(themeStore.effective.accentColor)
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider().overlay(themeStore.effective.textColor.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if vm.sanMoves.isEmpty {
                            Text("No moves yet.")
                                .font(.footnote).foregroundStyle(themeStore.effective.textColor.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal).padding(.vertical, 6)
                        }
                        ForEach(0..<rowCount, id: \.self) { row in
                            moveRow(row)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: vm.sanMoves.count) { _, _ in
                    if rowCount > 0 { withAnimation { proxy.scrollTo(rowCount - 1, anchor: .bottom) } }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .gemmaGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private func moveRow(_ row: Int) -> some View {
        let whiteIdx = row * 2
        let blackIdx = whiteIdx + 1
        HStack(spacing: 0) {
            Text("\(row + 1).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(themeStore.effective.textColor.opacity(0.45))
                .frame(width: 34, alignment: .leading)
            plyCell(index: whiteIdx)
            if blackIdx < vm.sanMoves.count {
                plyCell(index: blackIdx)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
        .id(row)
    }

    @ViewBuilder
    private func plyCell(index: Int) -> some View {
        let isActive = activePly == index
        Text(vm.sanMoves[index])
            .font(.callout.weight(isActive ? .bold : .regular))
            .foregroundStyle(isActive ? themeStore.effective.accentColor : themeStore.effective.textColor.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? themeStore.effective.accentColor.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { vm.viewTo(ply: index) }
    }
}
