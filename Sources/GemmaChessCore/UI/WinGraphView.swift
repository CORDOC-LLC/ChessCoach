//  WinGraphView.swift
//  A simple win% line/area graph over the game timeline. The horizontal axis is the
//  node index; the vertical axis is win% from White's perspective. Tapping or dragging
//  scrubs to the nearest node.

import SwiftUI

public struct WinGraphView: View {
    /// Win% from White's perspective per node (0...100).
    public var values: [Double]
    /// Currently-selected node index.
    public var currentIndex: Int
    /// Called with the node index when the user taps/scrubs.
    public var onScrub: (Int) -> Void

    public init(values: [Double], currentIndex: Int, onScrub: @escaping (Int) -> Void) {
        self.values = values
        self.currentIndex = currentIndex
        self.onScrub = onScrub
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(values.count, 1)
            let stepX = n > 1 ? w / CGFloat(n - 1) : w

            ZStack {
                // 50% midline.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                if values.count >= 2 {
                    // Filled area under the curve.
                    area(w: w, h: h, stepX: stepX)
                        .fill(Color.accentColor.opacity(0.18))
                    // The curve itself.
                    line(w: w, h: h, stepX: stepX)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }

                // Current-node marker.
                if values.indices.contains(currentIndex) {
                    let x = CGFloat(currentIndex) * stepX
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    .stroke(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let idx = Int((value.location.x / max(stepX, 0.001)).rounded())
                        onScrub(min(max(idx, 0), values.count - 1))
                    }
            )
        }
        .frame(height: 56)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func y(_ v: Double, h: CGFloat) -> CGFloat {
        // win% 100 → top, 0 → bottom.
        h * (1 - CGFloat(max(0, min(100, v)) / 100))
    }

    private func line(w: CGFloat, h: CGFloat, stepX: CGFloat) -> Path {
        Path { p in
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: CGFloat(i) * stepX, y: y(v, h: h))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func area(w: CGFloat, h: CGFloat, stepX: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            for (i, v) in values.enumerated() {
                p.addLine(to: CGPoint(x: CGFloat(i) * stepX, y: y(v, h: h)))
            }
            p.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: h))
            p.closeSubpath()
        }
    }
}
