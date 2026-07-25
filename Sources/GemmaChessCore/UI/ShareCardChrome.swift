//  ShareCardChrome.swift
//  The one branded frame every share card sits in (plan 2026-07-25-002, U2).
//
//  Before this existed, `GameResultShareCard`, `PuzzleRushShareCard`, and
//  `StreakShareCard` each carried their own near-identical copy of the same
//  background, emblem, wordmark, and size constant. Share cards are this app's
//  reach vehicle; three frames that can drift is the wrong shape for that.
//
//  TWO DELIBERATE CHANGES FROM THE COPIES THIS REPLACES:
//
//  1. BRANDING MOVED TO THE FOOTER. It used to sit on top, above the content.
//     Shareable-card convention is unanimous that the wordmark must not compete
//     with the hero -- and now that the hero is a chessboard, a large wordmark
//     above it would be exactly that competition.
//
//  2. THE THEME NAME IS REPLACED BY THE DOMAIN. "THE GAMBIT ROOM" means
//     something to the player who picked it and nothing to a stranger seeing
//     the card in a feed. `chesscoach.im` is the only element on the card that
//     can turn a viewer into a user, which is the entire point of sharing it.

import SwiftUI

/// Non-generic home for the shared size constant. A generic type cannot hold a
/// static stored property, so this can't live on `ShareCardChrome` itself.
public enum ShareCard {
    /// 4:5 — the best all-round social feed ratio, and 1080×1350 once rendered
    /// at 3x. The previous 360×480 (3:4) got cropped in portrait feeds.
    public static let size = CGSize(width: 360, height: 450)

    /// Where a viewer goes. Also attached to the share sheet as a second item
    /// so link-capable targets render a tappable link beside the image.
    public static let destination = "chesscoach.im"
    public static let destinationURL = URL(string: "https://chesscoach.im")
}

/// Wraps one share card's content in the app's branded frame.
public struct ShareCardChrome<Content: View>: View {
    private let content: Content
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            theme.bgColor
            theme.backgroundGradient
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer
            }
            .padding(20)
        }
        .frame(width: ShareCard.size.width, height: ShareCard.size.height)
    }

    /// Small, bottom, and never competing with the hero — but legible when the
    /// whole card is scaled down to a feed thumbnail, which is the only size
    /// that actually matters for reach.
    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accentColor)
            Text("ChessCoach")
                .font(theme.type.displayFont(size: 17))
                .foregroundStyle(theme.textColor)
                .tracking(theme.type.letterSpacing)
                .textCase(theme.type.uppercased ? .uppercase : nil)
            Spacer(minLength: 8)
            Text(ShareCard.destination)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(theme.accent2Color)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.cardBorderColor)
                .frame(height: 1)
        }
    }
}
