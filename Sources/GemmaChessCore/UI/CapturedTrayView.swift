//  CapturedTrayView.swift
//  A slim, content-width row of one side's captured pieces as small icons plus the
//  net material delta ("+N") when that side is ahead. Pure presentation — the caller
//  passes the already-diffed pieces (see `CapturedMaterial`). Deliberately tiny and
//  unboxed so it can sit inline in the info strip without eating vertical space.
//  Wraps onto extra rows instead of overflowing the screen when one side has
//  captured a lot of material (e.g. many pawns late in a long game).
//
//  A newly-arrived piece flashes briefly. The engine replies fast enough that a
//  capture can otherwise pass unnoticed -- the piece simply vanishes from the
//  board and silently appears here -- so the new glyph pops, rings, and settles
//  over about a second. Only ADDITIONS flash: taking a move back removes a
//  piece, which shouldn't read as a fresh capture.

import SwiftUI

struct CapturedTrayView: View {
    /// Captured pieces (FEN chars) to render, sorted by value.
    let pieces: [Character]
    /// Net material advantage for this side, shown as "+N" when positive.
    let advantage: Int
    /// Glyph size; small by default for the inline strip.
    var size: CGFloat = 15
    @Environment(ThemeStore.self) private var themeStore

    /// Index of the piece currently flashing, or nil when nothing is. Cleared
    /// by `flashTask` after the hold, so a rapid second capture restarts the
    /// animation rather than stacking two overlapping fades.
    @State private var flashIndex: Int?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        WrappingRow(spacing: 2, rowSpacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, ch in
                // A black piece's art is a near-black silhouette -- a faint
                // backdrop still isn't enough contrast against this app's dark
                // background (confirmed on-device: a 14%-white circle still
                // read as black-on-black). Black pieces get a properly light
                // chip so the glyph actually pops; white pieces already
                // contrast fine against the dark background on their own, so
                // a light chip there would invert the problem (white-on-white).
                let flashing = flashIndex == index
                BoardPiece(ch: ch, size: size)
                    .padding(3)
                    .background(Circle().fill(ch.isLowercase
                        ? Color.white.opacity(0.85)
                        : Color.white.opacity(0.10)))
                    .overlay(
                        Circle()
                            .strokeBorder(themeStore.effective.accent2Color,
                                          lineWidth: flashing ? 2 : 0)
                            .opacity(flashing ? 1 : 0)
                    )
                    .shadow(color: themeStore.effective.accent2Color.opacity(flashing ? 0.9 : 0),
                            radius: flashing ? 6 : 0)
                    .scaleEffect(flashing ? 1.5 : 1)
                    .zIndex(flashing ? 1 : 0)
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(themeStore.effective.accentColor)
                    .padding(.leading, 2)
            }
        }
        .frame(minHeight: size + 10)
        .onChange(of: pieces) { old, new in flash(from: old, to: new) }
        .onDisappear { flashTask?.cancel() }
    }

    /// Starts the flash when `new` gained a piece. `scaleEffect` is a geometry
    /// effect and `WrappingRow` measures children unscaled, so the pop never
    /// reflows the row or nudges its neighbours.
    private func flash(from old: [Character], to new: [Character]) {
        guard let index = Self.addedIndex(from: old, to: new) else { return }
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { flashIndex = index }
            // Long enough to actually register after a fast engine reply,
            // short enough not to linger into the next move.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { flashIndex = nil }
        }
    }

    /// Index in `new` of a piece kind that wasn't in `old`, or nil if nothing
    /// was added (a take-back, a jump backwards through history, a no-op).
    /// Duplicate glyphs are interchangeable, so flashing the first occurrence
    /// of the gained kind is visually identical to flashing "the" new one.
    static func addedIndex(from old: [Character], to new: [Character]) -> Int? {
        guard new.count > old.count else { return nil }
        var remaining: [Character: Int] = [:]
        for ch in old { remaining[ch, default: 0] += 1 }
        for (index, ch) in new.enumerated() {
            if let count = remaining[ch], count > 0 {
                remaining[ch] = count - 1
            } else {
                return index
            }
        }
        return nil
    }
}

/// A leading-aligned flow layout: children lay out left-to-right and wrap to a
/// new row when the proposed width runs out, instead of overflowing.
struct WrappingRow: Layout {
    var spacing: CGFloat = 2
    var rowSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                x = 0; y += rowHeight + rowSpacing; rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y + s.height / 2),
                anchor: .leading,
                proposal: ProposedViewSize(s)
            )
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
