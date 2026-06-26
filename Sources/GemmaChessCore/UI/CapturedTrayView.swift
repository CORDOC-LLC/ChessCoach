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
        HStack(spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, ch in
                BoardPiece(ch: ch, size: size)
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(GemmaTheme.accent)
                    .padding(.leading, 2)
            }
        }
        .frame(height: size + 3)
    }
}
