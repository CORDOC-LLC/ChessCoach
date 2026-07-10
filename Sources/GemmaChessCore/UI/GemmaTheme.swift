//  GemmaTheme.swift
//  Non-palette visual helpers: reusable glass/press styles and markdown
//  rendering. The palette itself lives in `Theme`/`ThemeStore` (see
//  Sources/GemmaChessCore/Theme/) -- this file used to also hold a static
//  `GemmaTheme.accent`/`.boardLight`/etc. palette, now retired in favor of
//  the user-editable Theme model (Living Themes).
//
//  Liquid Glass rules (per Apple WWDC25): glass lives on the navigation/floating
//  layer, never on content (the board, lists). Standard controls adopt Liquid Glass
//  automatically under Xcode 26; the helpers here add glass to our CUSTOM floating
//  panels, with an `.ultraThinMaterial` fallback below iOS 26.

import SwiftUI

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
    /// Apply the app's dark theme + accent + refracting background, keyed off
    /// the given `Theme`, in one call.
    func gemmaChrome(theme: Theme) -> some View {
        self
            .tint(theme.accentColor)
            .background(
                ZStack {
                    theme.bgColor
                    theme.backgroundGradient
                }
                .ignoresSafeArea()
            )
            .preferredColorScheme(theme.isLightBackground ? .light : .dark)
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
