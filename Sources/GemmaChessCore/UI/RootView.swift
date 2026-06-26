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
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("GemmaChess").font(.largeTitle.bold())
            Text("Play a game with an on-device coach, or review one of yours.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 14) {
                Button(action: onPlay) {
                    Label("Play a game", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onReview) {
                    Label("Review a game", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .navigationTitle("GemmaChess")
    }
}
