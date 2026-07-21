//  GameImportNudgeTests.swift
//  U7 — after a successful account import in `GameImportView`, a small callout
//  nudges the user toward the Weakness Report. The decision of whether to show
//  it is extracted into `GameImportView.shouldShowImportNudge`, a pure static
//  function, so it's testable without driving SwiftUI `@State` directly.

import Testing
@testable import GemmaChessCore

struct GameImportNudgeTests {

    @Test("Successful fetch with 1+ games shows the nudge")
    func nudgeShowsWithGames() {
        let games = ["[Event \"?\"]\n\n1. e4 e5 *"]
        #expect(GameImportView.shouldShowImportNudge(games: games, fetchError: nil) == true)
    }

    @Test("Successful fetch with zero games (valid empty response) hides the nudge")
    func nudgeHiddenWithEmptyGames() {
        #expect(GameImportView.shouldShowImportNudge(games: [], fetchError: nil) == false)
    }

    @Test("A failed fetch hides the nudge, regardless of GameImportError case", arguments: [
        GameImportError.userNotFound,
        GameImportError.network("offline"),
        GameImportError.http(500, "boom"),
    ])
    func nudgeHiddenOnFailure(error: GameImportError) {
        #expect(GameImportView.shouldShowImportNudge(games: [], fetchError: error) == false)
    }
}
