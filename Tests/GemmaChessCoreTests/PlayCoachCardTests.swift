//  PlayCoachCardTests.swift
//  U7 — the structured coach card: classification → colour mapping, the verdict's
//  better-move presence, and Markdown rendering of the focus line.

import Testing
import SwiftUI
@testable import GemmaChessCore

struct PlayCoachCardTests {

    @Test func classificationColours() {
        let theme = Theme.gambit
        #expect(MoveVerdict.color(for: "best", theme: theme) == theme.accentColor)
        #expect(MoveVerdict.color(for: "good", theme: theme) == theme.accentColor)
        #expect(MoveVerdict.color(for: "inaccuracy", theme: theme) == theme.accent2Color)
        #expect(MoveVerdict.color(for: "mistake", theme: theme) == Color.orange)
        #expect(MoveVerdict.color(for: "blunder", theme: theme) == Color.red)
    }

    @Test func blunderVerdictNamesBetterMove() {
        let v = MoveVerdict(moveSAN: "Qh5", classification: "blunder",
                            isBest: false, betterMoveSAN: "Nf3")
        #expect(MoveVerdict.color(for: v.classification, theme: .gambit) == Color.red)
        #expect(v.isBest == false)
        #expect(v.betterMoveSAN == "Nf3")
    }

    @Test func bestVerdictHasNoBetterMove() {
        // The VM nils out betterMove when the move is the engine's top choice.
        let v = MoveVerdict(moveSAN: "Nf3", classification: "best",
                            isBest: true, betterMoveSAN: nil)
        #expect(MoveVerdict.color(for: v.classification, theme: .gambit) == Theme.gambit.accentColor)
        #expect(v.betterMoveSAN == nil)
    }

    @Test func focusLineMarkdownHasNoLiteralAsterisks() {
        let rendered = "Develop your **knights** first".asCoachMarkdown
        let plain = String(rendered.characters)
        #expect(plain == "Develop your knights first")
        #expect(!plain.contains("*"))
    }
}
