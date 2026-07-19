//  ReviewPromptView.swift
//  The custom soft-ask sheet shown ahead of Apple's real App Store review
//  prompt (plan R8/KTD-6). This view never implements its own rating UI --
//  it only asks whether now's a good moment, then either calls the system
//  `requestReview()` action (backed by `SKStoreReviewController`) or backs
//  off, per Apple's guidelines against custom review flows. Callers gate
//  presentation with `ReviewPromptStore.shouldPrompt(...)`; both choices here
//  count as "shown" for that store's cooldown/cap bookkeeping (KTD-6), so
//  `recordShown()` is called on both paths.

import SwiftUI

public struct ReviewPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(ThemeStore.self) private var themeStore

    public init() {}

    private var theme: Theme { themeStore.effective }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.accentColor)
                .padding(.top, 32)

            Text("Enjoying ChessCoach?")
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.textColor)

            Text("Ratings help us keep building ChessCoach and shipping new features. "
                + "If it's been useful, a quick rating would mean a lot.")
                .font(.subheadline)
                .foregroundStyle(theme.mutedTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    requestReview()
                    ReviewPromptStore.recordShown()
                    dismiss()
                } label: {
                    Text("Rate ChessCoach")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(theme.onAccentColor)
                        .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    ReviewPromptStore.recordShown()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.mutedTextColor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .padding(.bottom, 16)
        .background(theme.bgColor)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
