//  YouTubePlayerView.swift
//  A minimal cross-platform embedded YouTube player, backed by WKWebView
//  loading YouTube's own `/embed/{videoID}` iframe endpoint — the standard,
//  documented embed surface (not scraping or reverse-engineering anything).

import SwiftUI
import WebKit

public struct YouTubePlayerView: View {
    let videoID: String

    public init(videoID: String) {
        self.videoID = videoID
    }

    public var body: some View {
        YouTubeWebView(videoID: videoID)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}

#if os(iOS)
import UIKit

private struct YouTubeWebView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = YouTubeEmbed.url(for: videoID) else { return }
        webView.load(URLRequest(url: url))
    }
}
#elseif os(macOS)
import AppKit

private struct YouTubeWebView: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url = YouTubeEmbed.url(for: videoID) else { return }
        webView.load(URLRequest(url: url))
    }
}
#endif

/// The one place that knows YouTube's embed URL shape — kept separate so it's
/// trivially testable without a live WKWebView.
enum YouTubeEmbed {
    static func url(for videoID: String) -> URL? {
        URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1")
    }

    /// YouTube's standard thumbnail CDN pattern (`img.youtube.com/vi/{id}/...`)
    /// — a documented, stable URL shape, not a per-video guess.
    static func thumbnailURL(for videoID: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }
}
