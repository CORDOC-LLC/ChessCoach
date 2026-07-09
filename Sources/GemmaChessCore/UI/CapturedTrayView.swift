//  CapturedTrayView.swift
//  A slim, content-width row of one side's captured pieces as small icons plus the
//  net material delta ("+N") when that side is ahead. Pure presentation — the caller
//  passes the already-diffed pieces (see `CapturedMaterial`). Deliberately tiny and
//  unboxed so it can sit inline in the info strip without eating vertical space.

import SwiftUI

struct CapturedTrayView: View {
    /// Captured pieces (FEN chars) to render, sorted by value.
    let pieces: [Character]
    /// Net material advantage for this side, shown as "+N" when positive.
    let advantage: Int
    /// Glyph size; small by default for the inline strip.
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, ch in
                // A black piece's art is a near-black silhouette -- invisible
                // against this app's dark background outside the board (where
                // a light/dark square would normally give it contrast). A soft
                // light backdrop chip fixes that for every piece, not just
                // black ones, so it doesn't need to special-case color.
                BoardPiece(ch: ch, size: size)
                    .padding(3)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(GemmaTheme.accent)
                    .padding(.leading, 2)
            }
        }
        .frame(height: size + 10)
    }
}
