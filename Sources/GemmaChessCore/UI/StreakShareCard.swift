//  StreakShareCard.swift
//  A themed, shareable "streak milestone" card for `PuzzleStreakStore`'s
//  daily-solve streak (plan U5, reuses U4's `ShareCardRenderer`/card
//  pattern). Deliberately NOT tied to live streak state -- it takes a plain
//  `streak` value so it can be rendered off the interactive view tree and is
//  trivially testable. Styled to match `GameResultShareCard`'s layout and
//  the app's card language.
//
//  The share affordance for this card is only meant to be shown by callers
//  at a milestone streak value (see `StreakMilestones.isMilestone(_:)`) --
//  not on every day's solve, so the button doesn't feel like noise. The card
//  view itself has no opinion on that; it just renders whatever streak it's
//  given.

import SwiftUI

/// The fixed milestone list a daily streak is checked against, and the pure
/// boundary check callers use to decide whether to surface a share
/// affordance for a just-updated streak (plan U5).
///
/// Milestones: 5, 10, 30, 50, 100 days -- the illustrative list from the
/// plan (origin: docs/plans/2026-07-21-001-feat-competitor-review-improvement-bundle-plan.md,
/// U5), kept as-is since no other requirement narrowed it further.
public enum StreakMilestones {
    public static let values: [Int] = [5, 10, 30, 50, 100]

    /// True only if `streak` is exactly one of `values` -- a streak that
    /// merely exceeds a milestone (e.g. 11) is not itself a milestone day.
    public static func isMilestone(_ streak: Int) -> Bool {
        values.contains(streak)
    }
}

/// A fixed-size share card celebrating a daily-streak milestone.
public struct StreakShareCard: View {
    public let streak: Int

    /// The size this card is designed to be rendered at. `ShareCardRenderer`
    /// callers should render at this size for the intended layout.
    public static let cardSize = CGSize(width: 360, height: 480)

    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(streak: Int) {
        self.streak = streak
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
                    Image(systemName: "flame.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(theme.accent2Color)
                    Text("\(streak)-day streak!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.textColor)
                    Text("Solved at least one puzzle every day for \(streak) days.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
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
        Image(systemName: "flame.fill")
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
}
