//  SavedGameStoreTests.swift
//  On-device persistence for Play mode games: save/load round-trips (including
//  the Int-keyed moveNotes dictionary), listing sorted by recency, deletion, and
//  the in-progress-game-id pointer used to offer "Resume" on launch.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("SavedGameStore")
struct SavedGameStoreTests {

    private func tempBaseDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedGameStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private let standardStartFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private func sample(id: UUID = UUID(), updatedAt: Date = Date()) -> SavedGame {
        SavedGame(
            id: id, startedAt: updatedAt, updatedAt: updatedAt, playerIsWhite: true,
            startFEN: standardStartFEN, moves: ["e2e4", "e7e5"], sanMoves: ["e4", "e5"],
            fenHistory: [standardStartFEN,
                         "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
                         "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"],
            skill: 6, isGameOver: false, resultText: nil, openingName: "King's Pawn", openingECO: "C20",
            moveNotes: [0: "A classical opening move, claiming the center."], gameSummary: nil
        )
    }

    @Test("save then load round-trips every field, including the Int-keyed moveNotes")
    func roundTrips() throws {
        let dir = tempBaseDir()
        // Dates round-trip through ISO 8601 at millisecond precision, so use an
        // already-millisecond-aligned date -- an in-memory `Date()` carries more
        // precision than that and would never compare equal after reloading.
        let game = sample(updatedAt: Date(timeIntervalSince1970: 1_720_000_000.123))
        try SavedGameStore.save(game, baseDir: dir)

        let loaded = try #require(SavedGameStore.load(id: game.id, baseDir: dir))
        #expect(loaded == game)
        #expect(loaded.moveNotes[0] == "A classical opening move, claiming the center.")
    }

    @Test("loadAll returns every saved game, most-recently-updated first")
    func loadAllSortsByRecency() throws {
        let dir = tempBaseDir()
        let older = sample(updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = sample(updatedAt: Date(timeIntervalSince1970: 2000))
        try SavedGameStore.save(older, baseDir: dir)
        try SavedGameStore.save(newer, baseDir: dir)

        let all = SavedGameStore.loadAll(baseDir: dir)
        #expect(all.map(\.id) == [newer.id, older.id])
    }

    @Test("delete removes the game's file; loadAll and load no longer see it")
    func deleteRemoves() throws {
        let dir = tempBaseDir()
        let game = sample()
        try SavedGameStore.save(game, baseDir: dir)
        SavedGameStore.delete(id: game.id, baseDir: dir)

        #expect(SavedGameStore.load(id: game.id, baseDir: dir) == nil)
        #expect(SavedGameStore.loadAll(baseDir: dir).isEmpty)
    }

    @Test("deleteAll removes every saved game and clears the in-progress pointer")
    func deleteAllClearsEverythingAndThePointer() throws {
        let dir = tempBaseDir()
        let defaults = UserDefaults(suiteName: "SavedGameStoreTests-\(UUID().uuidString)")!
        let a = sample()
        let b = sample()
        try SavedGameStore.save(a, baseDir: dir)
        try SavedGameStore.save(b, baseDir: dir)
        SavedGameStore.setInProgressGameID(a.id, defaults: defaults)

        SavedGameStore.deleteAll(baseDir: dir, defaults: defaults)

        #expect(SavedGameStore.loadAll(baseDir: dir).isEmpty)
        #expect(SavedGameStore.inProgressGameID(defaults: defaults) == nil)
    }

    @Test("in-progress game id persists and clears via UserDefaults")
    func inProgressPointer() {
        let defaults = UserDefaults(suiteName: "SavedGameStoreTests-\(UUID().uuidString)")!
        #expect(SavedGameStore.inProgressGameID(defaults: defaults) == nil)

        let id = UUID()
        SavedGameStore.setInProgressGameID(id, defaults: defaults)
        #expect(SavedGameStore.inProgressGameID(defaults: defaults) == id)

        SavedGameStore.setInProgressGameID(nil, defaults: defaults)
        #expect(SavedGameStore.inProgressGameID(defaults: defaults) == nil)
    }
}
