//  CapturedTrayView.swift
//  A slim, content-width row of one side's captured pieces as small icons plus the
//  net material delta ("+N") when that side is ahead. Pure presentation — the caller
//  passes the already-diffed pieces (see `CapturedMaterial`). Deliberately tiny and
//  unboxed so it can sit inline in the info strip without eating vertical space.
//  Wraps onto extra rows instead of overflowing the screen when one side has
//  captured a lot of material (e.g. many pawns late in a long game).

import SwiftUI

struct CapturedTrayView: View {
    /// Captured pieces (FEN chars) to render, sorted by value.
    let pieces: [Character]
    /// Net material advantage for this side, shown as "+N" when positive.
    let advantage: Int
    /// Glyph size; small by default for the inline strip.
    var size: CGFloat = 15
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        WrappingRow(spacing: 2, rowSpacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, ch in
                // A black piece's art is a near-black silhouette -- a faint
                // backdrop still isn't enough contrast against this app's dark
                // background (confirmed on-device: a 14%-white circle still
                // read as black-on-black). Black pieces get a properly light
                // chip so the glyph actually pops; white pieces already
                // contrast fine against the dark background on their own, so
                // a light chip there would invert the problem (white-on-white).
                BoardPiece(ch: ch, size: size)
                    .padding(3)
                    .background(Circle().fill(ch.isLowercase
                        ? Color.white.opacity(0.85)
                        : Color.white.opacity(0.10)))
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(themeStore.effective.accentColor)
                    .padding(.leading, 2)
            }
        }
        .frame(minHeight: size + 10)
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
