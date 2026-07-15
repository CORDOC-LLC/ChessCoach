//  OnboardingView.swift
//  First-launch walkthrough: 4 pages introducing the app's main surfaces
//  (coach, best moves, board scanning, puzzles) and why grounding every
//  explanation in a real chess engine beats a chatbot that just guesses.
//  Replayable later from Settings ("How ChessCoach works").

import SwiftUI

struct OnboardingPage: Identifiable {
    let id = Int.random(in: Int.min...Int.max)
    let icon: String
    let title: String
    let body: String
    let footnote: String?

    init(icon: String, title: String, body: String, footnote: String? = nil) {
        self.icon = icon; self.title = title; self.body = body; self.footnote = footnote
    }
}

public struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(ThemeStore.self) private var themeStore
    @State private var pageIndex = 0
    @State private var showPaywall = false

    private var theme: Theme { themeStore.effective }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "graduationcap.fill",
            title: "A Coach Grounded in Real Analysis",
            body: "Most chess \"AI coaches\" are chatbots that guess. ChessCoach is different: Stockfish, "
                + "a real chess engine, calculates every line first -- your coach only ever writes about "
                + "what the engine actually found."
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "See the Best Move, Understand Why",
            body: "Get live hints as you play, the engine's top 3 choices after every move, and a plain-"
                + "English explanation of the reasoning -- not just a verdict, the \"why\" behind it."
        ),
        OnboardingPage(
            icon: "camera.viewfinder",
            title: "Scan Any Board",
            body: "Mid-game at a café or a club? Photograph the physical board and get instant analysis, "
                + "or jump straight into playing the position on your phone."
        ),
        OnboardingPage(
            icon: "puzzlepiece.fill",
            title: "Sharpen Your Tactics, Free",
            body: "Hundreds of curated puzzles, and full engine review -- every grade, every best move -- "
                + "always free. No subscription required to play smarter.",
            footnote: "ChessCoach Pro adds a written coach on top -- entirely optional."
        ),
    ]

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            skipRow
            TabView(selection: $pageIndex) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                    pageView(page).tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            pageDots
            controls
        }
        .background(
            ZStack { theme.bgColor; theme.backgroundGradient }.ignoresSafeArea()
        )
        .preferredColorScheme(theme.isLightBackground ? .light : .dark)
        .sheet(isPresented: $showPaywall, onDismiss: finish) {
            PaywallView().environment(themeStore)
        }
    }

    private var skipRow: some View {
        HStack {
            Spacer()
            if pageIndex < Self.pages.count - 1 {
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor.opacity(0.55))
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(theme.surfaceColor.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(theme.accentColor.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: 104, height: 104)
                    .shadow(color: theme.accentColor.opacity(0.34), radius: 36)
                Image(systemName: page.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(theme.accentColor)
            }
            VStack(spacing: 12) {
                Text(page.title)
                    .font(theme.type.displayFont(size: 26))
                    .foregroundStyle(theme.textColor)
                    .tracking(theme.type.letterSpacing)
                    .textCase(theme.type.uppercased ? .uppercase : nil)
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(.subheadline)
                    .foregroundStyle(theme.textColor.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                if let footnote = page.footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(theme.accent2Color)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 34)
            Spacer(minLength: 8)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? theme.accentColor : theme.textColor.opacity(0.2))
                    .frame(width: index == pageIndex ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
        .padding(.bottom, 18)
    }

    private var controls: some View {
        Button {
            if pageIndex < Self.pages.count - 1 {
                withAnimation { pageIndex += 1 }
            } else {
                OnboardingStore.markCompleted()
                if BuildChannel.current.requiresProEntitlement {
                    showPaywall = true
                } else {
                    finish()
                }
            }
        } label: {
            Text(pageIndex < Self.pages.count - 1 ? "Next" : "Get Started")
                .font(.headline)
                .foregroundStyle(theme.onAccentColor)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accentColor)
        .controlSize(.large)
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }

    private func finish() {
        OnboardingStore.markCompleted()
        onFinish()
    }
}
