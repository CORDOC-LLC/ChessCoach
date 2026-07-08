//  YouTubeEmbedTests.swift
//  The embed/thumbnail URL construction used by the Beginners page.

import Testing
@testable import GemmaChessCore

struct YouTubeEmbedTests {

    @Test("embed URL uses YouTube's documented /embed/ path with the given video ID")
    func embedURL() {
        let url = YouTubeEmbed.url(for: "IU6k-4rKf-g")
        #expect(url?.absoluteString == "https://www.youtube.com/embed/IU6k-4rKf-g?playsinline=1")
    }

    @Test("thumbnail URL uses YouTube's documented img.youtube.com CDN pattern")
    func thumbnailURL() {
        let url = YouTubeEmbed.thumbnailURL(for: "IU6k-4rKf-g")
        #expect(url?.absoluteString == "https://img.youtube.com/vi/IU6k-4rKf-g/hqdefault.jpg")
    }
}
