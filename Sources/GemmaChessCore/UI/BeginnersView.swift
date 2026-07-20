//  BeginnersView.swift
//  A curated starting point for players who are brand new to chess (and to
//  ChessCoach itself): a plain-language walkthrough of what the app's modes
//  do, a few specific well-regarded videos (embedded in-app), and channels
//  worth subscribing to for ongoing learning. Every video/channel URL below
//  was verified via web search against the actual current YouTube page
//  before being hardcoded here — not generated from memory.
//
//  Three collapsed sections (collapsed by default, unlike this session's
//  other DisclosureGroup screens which default-expand -- this page is long
//  enough, and skimmable enough by section title, that a first-time visitor
//  should see all three headers before committing to reading any one).

import SwiftUI

struct BeginnerVideo: Identifiable {
    let id: String            // YouTube video ID
    let title: String
    let channelName: String
    let note: String
}

struct BeginnerChannel: Identifiable {
    var id: String { channelURL }
    let name: String
    let channelURL: String
    let note: String
}

/// One entry in the "How to use the app?" walkthrough -- a mode/feature name
/// plus a plain-language explanation of what it does and when to reach for it.
struct AppGuideEntry: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let body: String
}

public struct BeginnersView: View {
    @State private var playingVideoID: String?
    @State private var expandedSections: Set<String> = []
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init() {}

    private let guideEntries: [AppGuideEntry] = [
        .init(
            icon: "play.fill", title: "Play a game",
            body: "Play against Stockfish (the same engine used by every serious chess site) at a "
                + "strength you pick. Turn on the coach to get a live written note after your moves, "
                + "best-move hints, and an end-of-game debrief -- or turn it off and just play. Games "
                + "checkpoint automatically, so you can close the app mid-game and resume later."
        ),
        .init(
            icon: "puzzlepiece.fill", title: "Puzzles",
            body: "Solve tactical puzzles grouped by rating band, or try Puzzle Rush for a timed run "
                + "across all of them. Puzzles are curated from the Lichess puzzle database and are "
                + "completely free -- no coach, no network, just Stockfish-verified positions."
        ),
        .init(
            icon: "book.fill", title: "Lessons",
            body: "A short, original explanation of one chess idea (forks, pins, back-rank mates, and "
                + "more), paired with a handful of puzzles built for exactly that idea. Good for "
                + "learning a pattern on purpose rather than picking it up by accident."
        ),
        .init(
            icon: "book.closed.fill", title: "Opening trainer",
            body: "Practice named opening lines move by move, with hints and a coach panel. Lines you "
                + "get right come back less often; ones you miss come back sooner -- spaced repetition, "
                + "so you're not wasting time re-drilling openings you already know cold."
        ),
        .init(
            icon: "magnifyingglass", title: "Review a game",
            body: "Paste in or import a PGN (from a file, or linked from your Chess.com/Lichess account) "
                + "and get a full accuracy breakdown -- every mistake flagged, with the engine's "
                + "preferred move instead, plus an end-of-game summary."
        ),
        .init(
            icon: "camera.viewfinder", title: "Scan a board",
            body: "Point your camera at a physical chess board and the app reads the position "
                + "straight into a game you can keep playing or analyzing -- no manual setup needed."
        ),
        .init(
            icon: "sparkles", title: "Weakness Report",
            body: "Once you've played a few games, your coach can point out a specific recurring "
                + "pattern in your play -- a tactic you keep missing, a phase of the game that costs "
                + "you the most -- and point you at a Lesson or puzzle theme to work on it."
        ),
    ]

    private let videos: [BeginnerVideo] = [
        .init(
            id: "IU6k-4rKf-g",
            title: "Learn How to Play Chess for Beginners in Less Than 8 Minutes",
            channelName: "Chess.com",
            note: "Start here if you don't know how the pieces move yet."
        ),
        .init(
            id: "ej_fnsdsksA",
            title: "How To Play Chess: Learn All The Rules Of The Royal Game",
            channelName: "Chess.com",
            note: "A longer, more thorough pass over the full rules — check, checkmate, castling, en passant."
        ),
        .init(
            id: "d5n_RuvnmCo",
            title: "Gotham Chess Guide Part 1: 1000+",
            channelName: "GothamChess",
            note: "Once you know the rules, this is the natural next step — common tactical mistakes at beginner level."
        ),
    ]

    private let channels: [BeginnerChannel] = [
        .init(
            name: "GothamChess (IM Levy Rozman)",
            channelURL: "https://www.youtube.com/channel/UCQHX6ViZmPsWiYSFAyS0a3Q",
            note: "\"The Internet's Chess Teacher\" — the most-recommended channel for beginners; funny, clear, and covers openings/tactics/strategy."
        ),
        .init(
            name: "Hanging Pawns",
            channelURL: "https://www.youtube.com/channel/UCkJdvwRC-oGPhRHW_XPNokg",
            note: "Deep, structured opening and middlegame guides — great once you want to understand the WHY behind a move, not just memorize it."
        ),
        .init(
            name: "ChessBrah",
            channelURL: "https://www.youtube.com/channel/UCvXxdkt1d8Uu08NAQP2IUTw",
            note: "GMs Eric Hansen and Aman Hambleton — high-energy blitz games and commentary; good for picking up ideas by watching strong play."
        ),
        .init(
            name: "agadmator's Chess Channel",
            channelURL: "https://www.youtube.com/channel/UCL5YbN5WLFD8dLIegT5QAbA",
            note: "Famous-game breakdowns in plain language — a good way to enjoy chess and absorb patterns before you're ready for deep theory."
        ),
        .init(
            name: "Chess.com",
            channelURL: "https://www.youtube.com/channel/UC5kS0l76kC0xOzMPtOmSFGw",
            note: "The platform's own channel — structured beginner series, plus daily top-level commentary."
        ),
        .init(
            name: "Daniel Naroditsky",
            channelURL: "https://www.youtube.com/channel/UCHP9CdeguNUI-_nBv_UXBhw",
            note: "A beloved GM and teacher whose \"Speedrun\" series (climbing from a low rating on a fresh account) remains one of the best ways to see a master think out loud."
        ),
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New to chess? Start with how the app works, then the videos below, then "
                    + "subscribe to a few channels for ongoing lessons. None of this affects "
                    + "anything in the app — it's just a starting point.")
                    .font(.footnote)
                    .foregroundStyle(theme.textColor.opacity(0.6))

                section(id: "guide", title: "How to use the app?") {
                    VStack(spacing: 10) {
                        ForEach(guideEntries) { entry in
                            guideRow(entry)
                        }
                    }
                }

                section(id: "videos", title: "Videos to watch") {
                    VStack(spacing: 10) {
                        ForEach(videos) { video in
                            VideoRow(video: video, isPlaying: playingVideoID == video.id) {
                                playingVideoID = (playingVideoID == video.id) ? nil : video.id
                            }
                        }
                    }
                }

                section(id: "channels", title: "YouTube channels to follow") {
                    VStack(spacing: 10) {
                        ForEach(channels) { channel in
                            ChannelRow(channel: channel)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("New to Chess?")
    }

    /// A collapsed-by-default themed section, mirroring this app's other
    /// `DisclosureGroup` screens (Opening Trainer, Puzzles, Lessons) -- this
    /// page starts fully collapsed (unlike those) since a first-time visitor
    /// should see all three headers before committing to reading any one.
    @ViewBuilder
    private func section<Content: View>(
        id: String, title: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpandedBinding(for: id)) {
            content().padding(.top, 10)
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
        }
        .tint(theme.textColor)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedSections.insert(id) } else { expandedSections.remove(id) }
            }
        )
    }

    private func guideRow(_ entry: AppGuideEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accent2Color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text(entry.body).font(.caption).foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
        .padding(12)
        .background(theme.surfaceColor.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VideoRow: View {
    let video: BeginnerVideo
    let isPlaying: Bool
    let toggle: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textColor)
                        Text(video.channelName).font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                        Text(video.note).font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.plain)

            if isPlaying {
                YouTubePlayerView(videoID: video.id)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(theme.surfaceColor.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if !isPlaying, let url = YouTubeEmbed.thumbnailURL(for: video.id) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(16.0 / 9.0, contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 88, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(Image(systemName: "play.circle.fill").foregroundStyle(.white, .black.opacity(0.5)))
        } else {
            Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                .font(.title2)
                .foregroundStyle(theme.textColor)
                .frame(width: 88, height: 50)
        }
    }
}

private struct ChannelRow: View {
    let channel: BeginnerChannel
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text(channel.note).font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer(minLength: 8)
            if let url = URL(string: channel.channelURL) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(theme.surfaceColor.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
