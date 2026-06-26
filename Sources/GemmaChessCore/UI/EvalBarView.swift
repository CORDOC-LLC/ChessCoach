//  EvalBarView.swift
//  A thin vertical evaluation bar. The fill shows the win% for whichever side sits at
//  the bottom of the board, so it tracks the board's orientation.

import SwiftUI

public struct EvalBarView: View {
    /// Win% from White's perspective (0...100).
    public var winWhite: Double
    /// Whether White is at the bottom of the board.
    public var whiteAtBottom: Bool

    public init(winWhite: Double, whiteAtBottom: Bool = true) {
        self.winWhite = winWhite
        self.whiteAtBottom = whiteAtBottom
    }

    public var body: some View {
        GeometryReader { geo in
            // Fraction of the bar that is "white" (light) from the top.
            let whiteFrac = max(0, min(1, winWhite / 100))
            let bottomFrac = whiteAtBottom ? whiteFrac : (1 - whiteFrac)
            VStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.85))
                    .frame(height: geo.size.height * (1 - bottomFrac))
                Rectangle().fill(Color.white)
                    .frame(height: geo.size.height * bottomFrac)
            }
            .overlay(
                Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
            )
        }
        .frame(width: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityLabel("Evaluation")
        .accessibilityValue("White win chance \(Int(winWhite.rounded())) percent")
    }
}
