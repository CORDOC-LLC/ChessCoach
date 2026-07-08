//  SavedGame.swift
//  On-device persistence for Play mode games -- play-by-play (every FEN, every
//  SAN, every coach note), so a game can be resumed after the app is killed or
//  replayed move-by-move later. Distinct from `HistoryStore`, which stores a
//  compact analytics summary of an IMPORTED/analysed game (mistakes, accuracy) --
//  this stores the full move-by-move record of a game the user PLAYED, including
//  positions HistoryStore never needs (every intermediate FEN).
//
//  Everything here stays on-device: no saved game is ever sent anywhere. That's
//  worth being explicit about in the UI, since it's the one place in the app
//  that stores personal data at all.

import Foundation

/// One game played in Play mode, at whatever point it was last checkpointed --
/// either mid-game (resumable) or finished (replay-only, since `PlayViewModel.
/// tap` already refuses moves once `isGameOver` is true).
public struct SavedGame: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var updatedAt: Date
    public var playerIsWhite: Bool
    public var startFEN: String
    /// UCI moves in order, both sides.
    public var moves: [String]
    /// SAN moves in order, parallel to `moves`.
    public var sanMoves: [String]
    /// Position after each ply; `fenHistory[0] == startFEN`, so
    /// `fenHistory.count == moves.count + 1`.
    public var fenHistory: [String]
    public var skill: Int
    public var isGameOver: Bool
    public var resultText: String?
    public var openingName: String?
    public var openingECO: String?
    /// The coach's per-move note, keyed by the 0-based index into `moves` of the
    /// USER's move it explains (only user moves get a note -- see
    /// `PlayViewModel.streamCoachNote`). Absent for plies with no note, whether
    /// because the coach was off, unavailable, or the ply was the opponent's.
    public var moveNotes: [Int: String]
    /// The end-of-game written debrief, if the coach produced one.
    public var gameSummary: String?
    /// Every graded user move so far -- restored on resume so a game that's
    /// continued and later finishes still gets a full-quality debrief instead
    /// of one grounded only in moves played after the resume.
    public var moveRecords: [CoachPromptBuilder.PlayMoveRecord]

    public init(
        id: UUID, startedAt: Date, updatedAt: Date, playerIsWhite: Bool, startFEN: String,
        moves: [String], sanMoves: [String], fenHistory: [String], skill: Int,
        isGameOver: Bool, resultText: String?, openingName: String?, openingECO: String?,
        moveNotes: [Int: String], gameSummary: String?,
        moveRecords: [CoachPromptBuilder.PlayMoveRecord] = []
    ) {
        self.id = id; self.startedAt = startedAt; self.updatedAt = updatedAt
        self.playerIsWhite = playerIsWhite; self.startFEN = startFEN
        self.moves = moves; self.sanMoves = sanMoves; self.fenHistory = fenHistory
        self.skill = skill; self.isGameOver = isGameOver; self.resultText = resultText
        self.openingName = openingName; self.openingECO = openingECO
        self.moveNotes = moveNotes; self.gameSummary = gameSummary; self.moveRecords = moveRecords
    }

    /// Short label for a games list: "White vs Stockfish (skill 6)" etc.
    public var sideLabel: String { playerIsWhite ? "White" : "Black" }
}

/// On-device store for `SavedGame`s: one JSON file per game, so checkpointing
/// mid-game only rewrites that game's small file, not a shared log every ply.
public enum SavedGameStore {
    private static let inProgressKey = "savedGames.inProgressGameID"

    public static var defaultBaseDir: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GemmaChess/savedGames", isDirectory: true)
    }

    private static func path(for id: UUID, baseDir: URL) -> URL {
        baseDir.appendingPathComponent("\(id.uuidString).json")
    }

    /// Write (or overwrite) `game`'s file. Called after every ply, so this is
    /// the granularity a killed app can resume from.
    public static func save(_ game: SavedGame, baseDir: URL = defaultBaseDir) throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(game)
        try data.write(to: path(for: game.id, baseDir: baseDir), options: .atomic)
    }

    public static func load(id: UUID, baseDir: URL = defaultBaseDir) -> SavedGame? {
        guard let data = try? Data(contentsOf: path(for: id, baseDir: baseDir)) else { return nil }
        return try? Self.decoder.decode(SavedGame.self, from: data)
    }

    /// Every saved game, most-recently-updated first. Corrupt/unreadable files
    /// are skipped rather than failing the whole list.
    public static func loadAll(baseDir: URL = defaultBaseDir) -> [SavedGame] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil)) ?? []
        let games = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SavedGame? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(SavedGame.self, from: data)
            }
        return games.sorted { $0.updatedAt > $1.updatedAt }
    }

    public static func delete(id: UUID, baseDir: URL = defaultBaseDir) {
        try? FileManager.default.removeItem(at: path(for: id, baseDir: baseDir))
    }

    // MARK: - "Which game (if any) is resumable"

    /// The id of the in-progress game to offer resuming on launch, or nil.
    /// Cleared once a game ends (win/loss/draw/resign) -- a finished game is
    /// replay-only, not resumable, even though its file is kept.
    public static func inProgressGameID(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: inProgressKey).flatMap(UUID.init)
    }

    public static func setInProgressGameID(_ id: UUID?, defaults: UserDefaults = .standard) {
        if let id { defaults.set(id.uuidString, forKey: inProgressKey) }
        else { defaults.removeObject(forKey: inProgressKey) }
    }

    // MARK: - Codable plumbing
    //
    // `[Int: String]` (moveNotes) encodes/decodes fine via JSONEncoder/Decoder --
    // Foundation's Dictionary Codable conformance special-cases Int (and String)
    // keys to a JSON object keyed by the string form of the key, no manual
    // conversion needed.

    /// Plain `.iso8601` truncates to whole seconds, which would make a
    /// checkpoint-then-immediately-reload comparison (as in tests, or a resume
    /// right after a crash) see a different `updatedAt` than what was saved.
    /// A fresh formatter per call, not a shared static: `ISO8601DateFormatter`
    /// isn't `Sendable`.
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeISOFormatter().string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = makeISOFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format: \(string)")
        }
        return d
    }
}
