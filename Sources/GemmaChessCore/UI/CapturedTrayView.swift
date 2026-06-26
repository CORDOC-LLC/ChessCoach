//  CapturedTrayView.swift
//  A thin floating tray showing one side's captured pieces as small icons plus the
//  net material delta ("+N") when that side is ahead. Pure presentation — the caller
//  passes the already-diffed pieces (see `CapturedMaterial`). Lives on the glass
//  floating layer, never on the board.

import SwiftUI

struct CapturedTrayView: View {
    /// Captured pieces (FEN chars) to render, sorted by value.
    let pieces: [Character]
    /// Net material advantage for this side, shown as "+N" when positive.
    let advantage: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, ch in
                BoardPiece(ch: ch, size: 18)
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(GemmaTheme.accent)
                    .padding(.leading, 4)
            }
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .gemmaGlassPill()
    }
}
