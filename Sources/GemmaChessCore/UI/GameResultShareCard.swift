//  GameResultShareCard.swift
//  The card that actually leaves the app (plan 2026-07-25-002, U4). Takes a
//  plain `GameShareSummary` so it can be rendered off the live view tree by
//  `ShareCardRenderer` and stays trivially testable -- no view model, no
//  environment beyond the theme the caller injects.
//
//  BOARD-FIRST, NOT SCOREBOARD-FIRST. Neither Chess.com nor Lichess ships a
//  designed "result card": what they export is the position, as a diagram or a
//  GIF, and that is what circulates. Accuracy screenshots travel inward, into
//  chess forums, not outward to general audiences. So the board is the hero and
//  the result is a supporting line.
//
//  The hero is outcome-aware -- see `GameShareSummary.Hero`. Showing the final
//  position unconditionally would put a picture of the player's own king in
//  checkmate at the top of the card, which is the one thing a beginner will
//  never post.
//
//  No alarm red and no `flag.fill` on a loss: a flag reads as resignation, not
//  checkmate, and the result is already stated in words. Colour does not need
//  to editorialize.

import SwiftUI

/// A fixed-size share card summarizing one finished game.
public struct GameResultShareCard: View {
    public let summary: GameShareSummary
    /// Whether to print the running W/L/D tally. Off for the exported card by
    /// default: "0W 7L 0D" beside a checkmate is the exact demoralizing artifact
    /// this redesign set out to remove, and it reads even worse to a stranger
    /// than it does to the player.
    public let showsRecord: Bool

    /// The size this card renders at, shared with every other share card.
    public static let cardSize = ShareCard.size

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(summary: GameShareSummary, showsRecord: Bool = false) {
        self.summary = summary
        self.showsRecord = showsRecord
    }

    public var body: some View {
        ShareCardChrome {
            VStack(spacing: 12) {
                board
                if let caption = summary.hero.caption {
                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent2Color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                statsBlock
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Hero

    /// A static, non-interactive board. `ChessBoardView` takes every colour as
    /// an explicit parameter and reads no environment -- it was built to render
    /// previews like this -- so passing no `onTapSquare` is all that's needed to
    /// make it display-only.
    private var board: some View {
        ChessBoardView(
            fen: summary.hero.fen,
            orientation: summary.orientation,
            lastMove: summary.hero.lastMove.map { (from: $0.from, to: $0.to) },
            terminalExplanation: summary.hero.terminalExplanation,
            boardLight: theme.boardLightColor,
            boardDark: theme.boardDarkColor,
            highlightColor: theme.accent2Color,
            accentColor: theme.accentColor
        )
        .frame(width: 236, height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: Supporting strip

    private var statsBlock: some View {
        VStack(spacing: 8) {
            if let earned = summary.earnedHeadline {
                Text(earned)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            // Accuracy never ships as a bare number -- beginners don't know what
            // one means, which is why Chess.com benchmarks theirs to a school
            // grade. Suppressed entirely when nothing was graded rather than
            // rendering a meaningless 100%.
            if summary.hasGradedMoves {
                HStack(spacing: 6) {
                    Text("\(Int(summary.accuracy.rounded()))%")
                        .font(.headline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(theme.textColor)
                    Text(summary.band.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent2Color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Accuracy \(Int(summary.accuracy.rounded())) percent, \(summary.band.label)")

                qualityStrip
            }

            footerLine
        }
        .padding(.horizontal, 4)
    }

    /// Counts carry their labels as text, not colour alone -- a coloured dot
    /// says nothing to a colour-blind viewer or a screen reader.
    private var qualityStrip: some View {
        HStack(spacing: 10) {
            ForEach(summary.qualityCounts, id: \.classification) { item in
                HStack(spacing: 3) {
                    Circle()
                        .fill(MoveVerdict.color(for: item.classification, theme: theme))
                        .frame(width: 6, height: 6)
                    Text("\(item.count)")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(theme.textColor.opacity(0.9))
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(theme.textColor.opacity(0.6))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.qualityAccessibilityLabel)
    }

    private var footerLine: some View {
        VStack(spacing: 2) {
            if let opening = summary.openingName, !opening.isEmpty {
                Text(opening)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.accent2Color.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 6) {
                Text(summary.resultHeadline)
                    .font(.caption2)
                    .foregroundStyle(theme.textColor.opacity(0.55))
                if showsRecord {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(theme.textColor.opacity(0.3))
                    Text("\(summary.stats.wins)W \(summary.stats.losses)L \(summary.stats.draws)D")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.textColor.opacity(0.55))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}
