//  GemmaTheme.swift
//  The app's visual design system: a premium dark palette, a refracting background
//  for Liquid Glass to play against, board colours, and reusable glass/press styles.
//
//  Liquid Glass rules (per Apple WWDC25): glass lives on the navigation/floating
//  layer, never on content (the board, lists). Standard controls adopt Liquid Glass
//  automatically under Xcode 26; the helpers here add glass to our CUSTOM floating
//  panels, with an `.ultraThinMaterial` fallback below iOS 26.

import SwiftUI

public enum GemmaTheme {

    // MARK: Palette
    /// Emerald accent — also the colour of best-move hints, so the app feels of-a-piece.
    public static let accent = Color(red: 0.20, green: 0.83, blue: 0.60)
    public static let gold = Color(red: 1.0, green: 0.78, blue: 0.30)

    // Classic, recognizable board greens.
    public static let boardLight = Color(red: 0.92, green: 0.93, blue: 0.82)
    public static let boardDark = Color(red: 0.46, green: 0.59, blue: 0.34)
    public static let pieceWhite = Color(red: 0.98, green: 0.98, blue: 0.96)
    public static let pieceBlack = Color(red: 0.13, green: 0.12, blue: 0.11)

    // MARK: Background
    /// Rich dark backdrop with a soft emerald glow up top — gives Liquid Glass
    /// something to refract and lifts the whole app.
    public struct Background: View {
        public init() {}
        public var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.10, blue: 0.10),
                        Color(red: 0.04, green: 0.06, blue: 0.06),
                        Color(red: 0.02, green: 0.03, blue: 0.03),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [accent.opacity(0.18), .clear],
                    center: .init(x: 0.5, y: -0.1), startRadius: 10, endRadius: 460
                )
            }
            .ignoresSafeArea()
        }
    }

    public static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.65)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Glass helpers

public extension View {
    /// Liquid Glass card on iOS 26+, frosted material fallback below — for our own
    /// floating panels (status pill, coach card). Not for content lists/the board.
    func gemmaGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(GemmaGlass(shape: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))))
    }
    func gemmaGlassPill() -> some View {
        modifier(GemmaGlass(shape: AnyShape(Capsule())))
    }
    /// Apply the app's dark theme + accent + refracting background in one call.
    func gemmaChrome() -> some View {
        self
            .tint(GemmaTheme.accent)
            .background(GemmaTheme.Background())
            .preferredColorScheme(.dark)
    }
}

struct GemmaGlass: ViewModifier {
    let shape: AnyShape
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

public extension String {
    /// Render coach/LLM markdown (**bold**, *italic*, lists) inline while preserving
    /// line breaks — the on-device coach replies in light Markdown.
    var asCoachMarkdown: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
}

/// Subtle tactile press feedback (mirrors HypeBlitz's PressableStyle).
public struct PressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
