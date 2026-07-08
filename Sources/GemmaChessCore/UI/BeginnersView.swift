//  BeginnersView.swift
//  A curated starting point for players who are brand new to chess: a few
//  specific, well-regarded videos (embedded in-app) plus channels worth
//  subscribing to for ongoing learning. Every URL below was verified via web
//  search against the channel/video's actual current YouTube page before
//  being hardcoded here — not generated from memory, since a wrong video ID
//  or channel link just looks broken to the user.

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

public struct BeginnersView: View {
    @State private var playingVideoID: String?

    public init() {}

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
        List {
            Section {
                Text("New to chess? Start with the videos below, then subscribe to a "
                    + "few of these channels for ongoing lessons. None of this affects "
                    + "anything in the app — it's just a starting point.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Start here") {
                ForEach(videos) { video in
                    VideoRow(video: video, isPlaying: playingVideoID == video.id) {
                        playingVideoID = (playingVideoID == video.id) ? nil : video.id
                    }
                }
            }

            Section("Channels to subscribe to") {
                ForEach(channels) { channel in
                    ChannelRow(channel: channel)
                }
            }
        }
        .navigationTitle("New to Chess?")
    }
}

private struct VideoRow: View {
    let video: BeginnerVideo
    let isPlaying: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(video.channelName).font(.caption).foregroundStyle(.secondary)
                        Text(video.note).font(.caption).foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
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
                .frame(width: 88, height: 50)
        }
    }
}

private struct ChannelRow: View {
    let channel: BeginnerChannel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name).font(.subheadline.weight(.semibold))
                Text(channel.note).font(.caption).foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
    }
}
