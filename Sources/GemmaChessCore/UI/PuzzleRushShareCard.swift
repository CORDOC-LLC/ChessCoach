//  PuzzleRushShareCard.swift
//  A themed, shareable "how I did" card for a finished Puzzle Rush run (plan
//  U5, reuses U4's `ShareCardRenderer`/card pattern). Deliberately NOT tied to
//  a live `PuzzleRushSession` -- it takes plain values (`correctCount`,
//  `wrongAttempts`) so it can be rendered off the interactive view tree and
//  is trivially testable. Styled to match `GameResultShareCard`'s layout and
//  the app's card language (`theme.cardBackgroundColor`/`cardBorderColor`).

import SwiftUI

/// A fixed-size share card summarizing one finished Puzzle Rush run.
public struct PuzzleRushShareCard: View {
    public let correctCount: Int
    public let wrongAttempts: Int
    public let durationSeconds: Int

    /// The size this card is designed to be rendered at. `ShareCardRenderer`
    /// callers should render at this size for the intended layout.
    public static let cardSize = CGSize(width: 360, height: 480)

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(correctCount: Int, wrongAttempts: Int, durationSeconds: Int) {
        self.correctCount = correctCount
        self.wrongAttempts = wrongAttempts
        self.durationSeconds = durationSeconds
    }

    public var body: some View {
        ZStack {
            theme.bgColor
            theme.backgroundGradient
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                emblem
                VStack(spacing: 4) {
                    Text("ChessCoach")
                        .font(theme.type.displayFont(size: 30))
                        .foregroundStyle(theme.textColor)
                        .tracking(theme.type.letterSpacing)
                        .textCase(theme.type.uppercased ? .uppercase : nil)
                    Text(theme.name)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2.5)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.accent2Color)
                }

                VStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(theme.accent2Color)
                    Text("Puzzle Rush")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.textColor)
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    Text(durationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent2Color)
                        .padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(theme.cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    }

    private var emblem: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(theme.accentColor)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.surfaceColor.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.accentColor.opacity(0.45), lineWidth: 1)
                    )
            )
    }

    private var resultText: String {
        wrongAttempts > 0
            ? "Solved \(correctCount) puzzles, \(wrongAttempts) missed"
            : "Solved \(correctCount) puzzles"
    }

    private var durationLabel: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if seconds == 0 { return "\(minutes) minute run" }
        return String(format: "%d:%02d run", minutes, seconds)
    }
}
