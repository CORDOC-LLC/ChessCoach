//  ThemeTests.swift

import Testing
import SwiftUI
@testable import GemmaChessCore

@Suite("Theme")
struct ThemeTests {

    @Test("Gambit preset matches the design handoff's exact hex values")
    func gambitHexValues() {
        let t = Theme.gambit
        #expect(t.accent == "#2f8360")
        #expect(t.accent2 == "#c9a24b")
        #expect(t.bg == "#140f0a")
        #expect(t.surface == "#281e14")
        #expect(t.text == "#f3ead4")
        #expect(t.boardLight == "#e8d9b8")
        #expect(t.boardDark == "#6f4a2c")
        #expect(t.type == .elegant)
    }

    @Test("Daylight preset matches the design handoff's exact hex values")
    func daylightHexValues() {
        let t = Theme.daylight
        #expect(t.accent == "#5b8c6e")
        #expect(t.accent2 == "#bd7f56")
        #expect(t.bg == "#f2ecdf")
        #expect(t.surface == "#fffdf8")
        #expect(t.text == "#2f2a22")
        #expect(t.boardLight == "#ece4d2")
        #expect(t.boardDark == "#a7b795")
        #expect(t.type == .modern)
    }

    @Test("Night Market preset matches the design handoff's exact hex values")
    func nightHexValues() {
        let t = Theme.night
        #expect(t.accent == "#2fe090")
        #expect(t.accent2 == "#ffb648")
        #expect(t.bg == "#0a0d12")
        #expect(t.surface == "#101620")
        #expect(t.text == "#eafff5")
        #expect(t.boardLight == "#b9c6c0")
        #expect(t.boardDark == "#233f34")
        #expect(t.type == .bold)
    }

    @Test("The Study preset matches the design handoff's exact hex values")
    func studyHexValues() {
        let t = Theme.study
        #expect(t.accent == "#6f86b8")
        #expect(t.accent2 == "#c0a15e")
        #expect(t.bg == "#12141c")
        #expect(t.surface == "#1a1e2a")
        #expect(t.text == "#e7e3d6")
        #expect(t.boardLight == "#d5d8cf")
        #expect(t.boardDark == "#4a5570")
        #expect(t.type == .modern)
    }

    @Test("presets contains exactly the 4 built-ins in display order")
    func presetsOrder() {
        #expect(Theme.presets.map(\.id) == ["gambit", "daylight", "night", "study"])
    }

    @Test("onAccentColor picks dark text for a light accent")
    func onAccentForLightAccent() {
        // Daylight's accent (#5b8c6e) has luminance just under the 0.6 cutoff
        // in practice, so use an unambiguous light accent to pin the branch.
        var t = Theme.gambit
        t.accent = "#f0f0f0"
        #expect(t.onAccentColor == Color(hex: "#15120c"))
    }

    @Test("onAccentColor picks light text for a dark accent")
    func onAccentForDarkAccent() {
        var t = Theme.gambit
        t.accent = "#101010"
        #expect(t.onAccentColor == Color(hex: "#f7f3ea"))
    }

    @Test("Color(hex:) tolerates malformed input without crashing")
    func malformedHexFallsBackSafely() {
        let malformed = Color(hex: "not-a-color")
        #expect(malformed == Color(red: 0, green: 0, blue: 0))
        let tooShort = Color(hex: "#ab")
        #expect(tooShort == Color(red: 0, green: 0, blue: 0))
    }

    @Test("Color(hex:) supports the 3-digit shorthand")
    func shorthandHex() {
        #expect(Color(hex: "#fff") == Color(hex: "#ffffff"))
    }

    @Test("TypePersonality has exactly 4 cases with distinct letter-spacing/case treatment")
    func typePersonalityCoverage() {
        #expect(Theme.TypePersonality.allCases.count == 4)
        let spacings = Set(Theme.TypePersonality.allCases.map(\.letterSpacing))
        #expect(spacings.count == 4)
        #expect(Theme.TypePersonality.bold.uppercased)
        #expect(!Theme.TypePersonality.elegant.uppercased)
    }

    @Test("Theme round-trips through JSON encoding losslessly")
    func codableRoundTrip() throws {
        var custom = Theme.gambit
        custom.id = "c123"
        custom.name = "My Theme"
        custom.kind = .custom
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == custom)
    }

    @Test("ColorToken subscript reads and writes the matching stored property")
    func colorTokenSubscript() {
        var t = Theme.gambit
        t[.accent] = "#123456"
        #expect(t.accent == "#123456")
        #expect(t[.accent] == "#123456")
    }
}
