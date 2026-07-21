//  GameResultShareCard.swift
//  A themed, shareable "I just played this" card for a finished Play-mode
//  game (plan U4 / KTD-4). Deliberately NOT tied to live game state -- it
//  takes plain values so it can be rendered off the interactive view tree via
//  `ShareCardRenderer` and so it's trivially testable. Styled to match the
//  app's card language (`theme.cardBackgroundColor`/`cardBorderColor`, see
//  RootView's emblem and WeaknessReportView's `card(...)` helper).

import SwiftUI

/// A fixed-size share card summarizing one finished game's result.
public struct GameResultShareCard: View {
    public let resultText: String
    public let outcome: PlayOutcome
    public let openingName: String?

    /// The size this card is designed to be rendered at. `ShareCardRenderer`
    /// callers should render at this size for the intended layout.
    public static let cardSize = CGSize(width: 360, height: 480)

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(resultText: String, outcome: PlayOutcome, openingName: String?) {
        self.resultText = resultText
        self.outcome = outcome
        self.openingName = openingName
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
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.textColor)
                    Text(resultText)
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    if let openingName, !openingName.isEmpty {
                        Text(openingName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent2Color)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 2)
                    }
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
        Image(systemName: "crown.fill")
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

    private var icon: String {
        switch outcome {
        case .win: return "crown.fill"
        case .loss: return "flag.fill"
        case .draw: return "equal.circle.fill"
        }
    }

    private var title: String {
        switch outcome {
        case .win: return "I won!"
        case .loss: return "Game over"
        case .draw: return "Draw"
        }
    }

    private var tint: Color {
        switch outcome {
        case .win: return theme.accent2Color
        case .loss: return .red
        case .draw: return theme.textColor.opacity(0.8)
        }
    }
}
