//  RootView.swift
//  The shared app entry. Both app shells embed `GemmaRootView()`. A Home screen
//  routes to Play mode (new game vs the engine, with live coaching) or Review mode
//  (paste/import a game and study it). Each mode runs in the navigation stack.

import SwiftUI

/// Retained for source compatibility with the app shells; the root is stack-based.
public enum GemmaLayoutStyle: Sendable {
    case automatic, column, split
}

public struct GemmaRootView: View {
    @State private var review = ReviewViewModel()
    @State private var play = PlayViewModel()
    @State private var mode: Mode = .home

    private enum Mode { case home, play, review }

    public init(style: GemmaLayoutStyle = .automatic) {}

    public var body: some View {
        NavigationStack {
            switch mode {
            case .home:
                HomeView(onPlay: { mode = .play }, onReview: { mode = .review })
            case .play:
                PlayContainerView(vm: play, onExit: { mode = .home })
            case .review:
                reviewFlow
            }
        }
        .gemmaChrome()
    }

    @ViewBuilder
    private var reviewFlow: some View {
        if review.session == nil {
            LoadView(vm: review)
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home") { mode = .home } } }
        } else {
            ReviewScreen(vm: review, onNewGame: { review.session = nil })
                .toolbar { ToolbarItem(placement: .topBarLeadingCompat) {
                    Button("Home") { review.session = nil; mode = .home }
                } }
        }
    }
}

/// Landing screen: choose Play or Review.
struct HomeView: View {
    var onPlay: () -> Void
    var onReview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(GemmaTheme.accentGradient)
                    .shadow(color: GemmaTheme.accent.opacity(0.5), radius: 18)
                VStack(spacing: 8) {
                    Text("ChessCoach")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Play with an on-device coach,\nor review one of your games.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 14) {
                Button(action: onPlay) {
                    Label("Play a game", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onReview) {
                    Label("Review a game", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
