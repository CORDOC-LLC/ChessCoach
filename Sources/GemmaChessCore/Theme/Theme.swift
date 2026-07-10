//  Theme.swift
//  The "Living Themes" model — replaces the old static `GemmaTheme` palette.
//  A `Theme` is 7 editable color tokens + a type personality (display font).
//  Everything else the app paints with (background gradient, contrast text,
//  muted/faint text, card style) is DERIVED from those 7 tokens, never stored,
//  so a user edit repaints the whole app consistently with no extra state.

import SwiftUI

public struct Theme: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case preset, custom
    }

    /// Selects the display font used for the wordmark and section titles.
    /// Body/UI text always stays the system font — only these get a
    /// personality. Mapped to the nearest built-in system font family rather
    /// than bundling the design reference's named fonts (Playfair Display /
    /// Instrument Serif / Bebas Neue / Hanken Grotesk).
    public enum TypePersonality: String, Codable, CaseIterable, Sendable, Identifiable {
        case elegant, modern, bold, clean

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .elegant: return "Elegant"
            case .modern: return "Modern"
            case .bold: return "Bold"
            case .clean: return "Clean"
            }
        }

        /// Nearest system-font equivalent to the design reference's named
        /// font for this personality, at the given point size.
        public func displayFont(size: CGFloat) -> Font {
            switch self {
            case .elegant:
                return .system(size: size, weight: .bold, design: .serif)
            case .modern:
                return .system(size: size, weight: .regular, design: .serif)
            case .bold:
                return .system(size: size, weight: .heavy, design: .default)
            case .clean:
                return .system(size: size, weight: .bold, design: .rounded)
            }
        }

        public var letterSpacing: CGFloat {
            switch self {
            case .elegant: return 0.5
            case .modern: return 0
            case .bold: return 2
            case .clean: return 0.3
            }
        }

        /// Bebas Neue reads as all-caps condensed; SwiftUI has no condensed
        /// system family, so uppercasing the text approximates the look.
        public var uppercased: Bool { self == .bold }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var type: TypePersonality

    // 7 editable color tokens, stored as hex strings for Codable simplicity.
    public var accent: String       // primary — buttons, emblem, coach, active states
    public var accent2: String      // highlight — hints, gold chips, opening label, black-piece rim
    public var bg: String           // base background (a gradient is derived from it)
    public var surface: String      // card/panel base (rendered at ~84% opacity)
    public var text: String         // primary text; muted/faint derived by opacity
    public var boardLight: String
    public var boardDark: String

    public init(
        id: String, name: String, kind: Kind, type: TypePersonality,
        accent: String, accent2: String, bg: String, surface: String, text: String,
        boardLight: String, boardDark: String
    ) {
        self.id = id; self.name = name; self.kind = kind; self.type = type
        self.accent = accent; self.accent2 = accent2; self.bg = bg
        self.surface = surface; self.text = text
        self.boardLight = boardLight; self.boardDark = boardDark
    }
}

// MARK: - Color accessors

public extension Theme {
    var accentColor: Color { Color(hex: accent) }
    var accent2Color: Color { Color(hex: accent2) }
    var bgColor: Color { Color(hex: bg) }
    var surfaceColor: Color { Color(hex: surface) }
    var textColor: Color { Color(hex: text) }
    var boardLightColor: Color { Color(hex: boardLight) }
    var boardDarkColor: Color { Color(hex: boardDark) }
}

// MARK: - Derived values (computed, never stored)

public extension Theme {
    /// Contrast-picked text color for content drawn on top of `accentColor` —
    /// relative luminance of `accent`; light text on a dark accent, dark text
    /// on a light accent, so labels stay legible on both a neon-green and a
    /// pale-sage accent.
    var onAccentColor: Color {
        let (r, g, b) = Color.hexComponents(accent)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? Color(hex: "#15120c") : Color(hex: "#f7f3ea")
    }

    var mutedTextColor: Color { textColor.opacity(0.55) }
    var faintTextColor: Color { textColor.opacity(0.38) }

    /// Soft radial glow behind the whole app, keyed off the active theme —
    /// gives Liquid Glass something to refract and lifts the background.
    var backgroundGradient: RadialGradient {
        RadialGradient(
            colors: [accent2Color.opacity(0.16), .clear],
            center: .init(x: 0.5, y: -0.08), startRadius: 10, endRadius: 460
        )
    }

    var cardBackgroundColor: Color { surfaceColor.opacity(0.84) }
    var cardBorderColor: Color { accent2Color.opacity(0.22) }

    /// Whether `bg` is light enough that the system chrome (status bar,
    /// keyboard, system controls) should render for a light background --
    /// same luminance formula as `onAccentColor`, applied to `bg` instead.
    var isLightBackground: Bool {
        let (r, g, b) = Color.hexComponents(bg)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
}

// MARK: - Presets

public extension Theme {
    static let gambit = Theme(
        id: "gambit", name: "The Gambit Room", kind: .preset, type: .elegant,
        accent: "#2f8360", accent2: "#c9a24b", bg: "#140f0a", surface: "#281e14",
        text: "#f3ead4", boardLight: "#e8d9b8", boardDark: "#6f4a2c"
    )
    static let daylight = Theme(
        id: "daylight", name: "Daylight", kind: .preset, type: .modern,
        accent: "#5b8c6e", accent2: "#bd7f56", bg: "#f2ecdf", surface: "#fffdf8",
        text: "#2f2a22", boardLight: "#ece4d2", boardDark: "#a7b795"
    )
    static let night = Theme(
        id: "night", name: "Night Market", kind: .preset, type: .bold,
        accent: "#2fe090", accent2: "#ffb648", bg: "#0a0d12", surface: "#101620",
        text: "#eafff5", boardLight: "#b9c6c0", boardDark: "#233f34"
    )
    static let study = Theme(
        id: "study", name: "The Study", kind: .preset, type: .modern,
        accent: "#6f86b8", accent2: "#c0a15e", bg: "#12141c", surface: "#1a1e2a",
        text: "#e7e3d6", boardLight: "#d5d8cf", boardDark: "#4a5570"
    )

    /// The 4 built-in presets, in display order.
    static let presets: [Theme] = [.gambit, .daylight, .night, .study]
}

// MARK: - Swatch palettes (curated quick-picks per editable token)

public extension Theme {
    enum ColorToken: String, CaseIterable, Sendable, Identifiable {
        case accent, accent2, bg, surface, boardLight, boardDark, text

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .accent: return "Accent · actions"
            case .accent2: return "Highlight"
            case .bg: return "Background"
            case .surface: return "Cards"
            case .boardLight: return "Board — light squares"
            case .boardDark: return "Board — dark squares"
            case .text: return "Text"
            }
        }
    }

    static let swatches: [ColorToken: [String]] = [
        .accent: ["#2f8360", "#5b8c6e", "#2fe090", "#6f86b8", "#c9772f", "#7c5cff"],
        .accent2: ["#c9a24b", "#bd7f56", "#ffb648", "#c0a15e", "#d98cae", "#9ab973"],
        .bg: ["#140f0a", "#0a0d12", "#12141c", "#16130f", "#f2ecdf", "#eef1ee"],
        .surface: ["#281e14", "#101620", "#1a1e2a", "#241c14", "#fffdf8", "#f6f2ea"],
        .boardLight: ["#e8d9b8", "#b9c6c0", "#ece4d2", "#d5d8cf", "#eaddc0", "#dfe6df"],
        .boardDark: ["#6f4a2c", "#233f34", "#a7b795", "#4a5570", "#5c4a30", "#7d8b6f"],
        .text: ["#f3ead4", "#eafff5", "#e7e3d6", "#ece2cf", "#2f2a22", "#1c1a16"],
    ]

    /// Get/set a token's hex string by `ColorToken`, so the editor UI can bind
    /// generically instead of a per-token switch at every call site.
    subscript(token: ColorToken) -> String {
        get {
            switch token {
            case .accent: return accent
            case .accent2: return accent2
            case .bg: return bg
            case .surface: return surface
            case .boardLight: return boardLight
            case .boardDark: return boardDark
            case .text: return text
            }
        }
        set {
            switch token {
            case .accent: accent = newValue
            case .accent2: accent2 = newValue
            case .bg: bg = newValue
            case .surface: surface = newValue
            case .boardLight: boardLight = newValue
            case .boardDark: boardDark = newValue
            case .text: text = newValue
            }
        }
    }
}

// MARK: - Color(hex:)

public extension Color {
    /// Parses `#RRGGBB` (or `RRGGBB`, or `#RGB`) into a `Color`. Malformed
    /// input never crashes — falls back to opaque black.
    init(hex: String) {
        let (r, g, b) = Color.hexComponents(hex)
        self.init(red: r, green: g, blue: b)
    }

    /// Shared parse used by both `init(hex:)` and `Theme.onAccentColor`'s
    /// luminance calculation, so they never disagree on what a hex string means.
    static func hexComponents(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy(\.isHexDigit) else { return (0, 0, 0) }
        switch s.count {
        case 3:
            let chars = Array(s)
            s = chars.flatMap { [$0, $0] }.map(String.init).joined()
        case 6:
            break
        default:
            return (0, 0, 0)
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return (0, 0, 0) }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return (r, g, b)
    }
}
