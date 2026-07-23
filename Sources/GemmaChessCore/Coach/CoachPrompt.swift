//  CoachPrompt.swift
//  Structured fact-shaping types for the coach. Text formatting and the coach
//  personas (chatInstructions/moveNoteInstructions/summaryInstructions,
//  chatPrompt/engineFactsText/gameFactsText/playGameFactsText/boardFactsText/
//  openingFactsText) used to live here and be sent to the gateway as a
//  finished {system, prompt} pair -- that logic now lives server-side
//  (chesscoach-gateway's coachChatPrompt.ts/coachSummaryPrompt.ts, ported
//  verbatim from what used to be here), so the actual coaching instructions
//  are never shipped in this open-source client (plan 2026-07-21-002, U1).
//
//  What remains here are the plain data structs that carry engine/game facts
//  from the client to the gateway as JSON -- `Codable` with field names that
//  match `/api/coach`'s wire contract exactly. `CoachOrchestrator` builds
//  these; `ManagedCoach` JSON-encodes them as-is.

import Foundation

// MARK: - Structured engine facts

/// Side being reviewed, used for game-summary phrasing and wire encoding
/// ("white"/"black" strings, matching the gateway's `playerSide`/`player`/
/// `color` fields).
public enum CoachSide: String, Sendable, Equatable, Codable { case white, black }

/// One near-best alternative line (an entry from multipv lines[1...]).
public struct CoachAltLine: Sendable, Equatable, Codable {
    public var firstSan: String
    public var eval: String        // pre-formatted, e.g. "±0.30" or "#4"
    public var winPercent: Double
    public init(firstSan: String, eval: String, winPercent: Double) {
        self.firstSan = firstSan; self.eval = eval; self.winPercent = winPercent
    }
}

/// Classification + refutation for a specific move the user asked about.
public struct CoachMoveInfo: Sendable, Equatable, Codable {
    public var moveSan: String
    public var classification: String
    public var winBefore: Double
    public var winAfter: Double
    public var winSwing: Double
    public var isEngineBest: Bool
    public var betterMoveSan: String?
    public var refutationLineSan: [String]
    public init(moveSan: String, classification: String, winBefore: Double, winAfter: Double,
                winSwing: Double, isEngineBest: Bool, betterMoveSan: String? = nil,
                refutationLineSan: [String] = []) {
        self.moveSan = moveSan; self.classification = classification
        self.winBefore = winBefore; self.winAfter = winAfter; self.winSwing = winSwing
        self.isEngineBest = isEngineBest; self.betterMoveSan = betterMoveSan
        self.refutationLineSan = refutationLineSan
    }
}

/// Engine read-out for one position (optionally about a played move) -- sent
/// to the gateway as `facts.current`/`facts.move` for chat/moveNote requests.
/// Mirrors the dict returned by the source `engine_line`.
public struct CoachLineInfo: Sendable, Equatable, Codable {
    public var bestSan: String?
    public var eval: String            // pre-formatted eval of the best line
    public var winPercent: Double
    public var lineSan: [String]
    public var alternatives: [CoachAltLine]
    public var move: CoachMoveInfo?
    public init(bestSan: String?, eval: String, winPercent: Double, lineSan: [String],
                alternatives: [CoachAltLine] = [], move: CoachMoveInfo? = nil) {
        self.bestSan = bestSan; self.eval = eval; self.winPercent = winPercent
        self.lineSan = lineSan; self.alternatives = alternatives; self.move = move
    }
}

/// One flagged move for the end-of-game summary facts.
public struct CoachFlaggedMove: Sendable, Equatable, Codable {
    public var moveNumber: Int
    public var color: CoachSide
    public var moveSan: String
    public var classification: String
    public var winBefore: Double
    public var winAfter: Double
    public var winSwing: Double
    public var bestMoveSan: String
    public var comment: String
    /// The position after this move, so the gateway can ground its commentary in a
    /// verified piece list (`boardFactsText`) instead of inferring the board from
    /// SAN alone. Optional: older callers/data that predate this field decode as
    /// nil (synthesized `Decodable` treats a missing key on an `Optional` property
    /// as absent, not an error), matching `PlayMoveRecord.bestUCI`'s precedent below.
    public var fen: String?
    public init(moveNumber: Int, color: CoachSide, moveSan: String, classification: String,
                winBefore: Double, winAfter: Double, winSwing: Double, bestMoveSan: String,
                comment: String, fen: String? = nil) {
        self.moveNumber = moveNumber; self.color = color; self.moveSan = moveSan
        self.classification = classification; self.winBefore = winBefore; self.winAfter = winAfter
        self.winSwing = winSwing; self.bestMoveSan = bestMoveSan; self.comment = comment
        self.fen = fen
    }
}

/// Pre-computed inputs for the game-summary facts block (imported games with
/// two known accuracies -- `ReviewViewModel`'s path). Sent to the gateway as
/// `facts` (with `source: "imported"`) for `kind: "summary"` requests.
public struct CoachGameInput: Sendable, Equatable, Codable {
    public var white: String
    public var black: String
    public var result: String
    public var opening: String?
    public var speed: String
    public var player: CoachSide
    public var accuracyWhite: Double
    public var accuracyBlack: Double
    public var mistakes: [CoachFlaggedMove]
    public init(white: String, black: String, result: String, opening: String?, speed: String,
                player: CoachSide, accuracyWhite: Double, accuracyBlack: Double,
                mistakes: [CoachFlaggedMove]) {
        self.white = white; self.black = black; self.result = result; self.opening = opening
        self.speed = speed; self.player = player; self.accuracyWhite = accuracyWhite
        self.accuracyBlack = accuracyBlack; self.mistakes = mistakes
    }
}

// MARK: - CoachPromptBuilder: what's left once the persona/formatting moved server-side

public enum CoachPromptBuilder {

    /// A plain-English listing of every piece on the board, by side, plus the side
    /// to move -- built deterministically from the FEN. This was previously fed to
    /// the model client-side (`boardFactsText`); the gateway now derives the same
    /// grounding server-side from `facts.fen`, so this helper is gone. Kept here
    /// only as a namespace anchor for `PlayMoveRecord` below (persisted data --
    /// see that type's header).

    /// One graded user move from a live Play game, for the end-of-game summary.
    /// Codable so `SavedGame` can persist it and restore full summary quality
    /// after a resumed game later ends. Sent to the gateway as one entry of
    /// `facts.records` (with `facts.source: "play"`) for `kind: "summary"`
    /// requests -- field names match the wire contract exactly.
    public struct PlayMoveRecord: Sendable, Equatable, Codable {
        public var moveNumber: Int
        public var san: String
        public var classification: String
        public var winBefore: Double
        public var winAfter: Double
        public var betterSan: String?
        /// The engine's top move at this ply, as UCI -- needed by `Motifs.tagMotifs`
        /// (which compares the played move against it), unlike `betterSan` which is
        /// only for display. Optional: older saved games persisted before this field
        /// existed decode it as nil (synthesized `Decodable` treats a missing key on
        /// an `Optional` property as absent, not an error), and the default `nil` in
        /// the memberwise init below keeps existing call sites compiling unchanged.
        public var bestUCI: String?
        /// The position after this move -- same board-grounding purpose as
        /// `CoachFlaggedMove.fen` above. Optional for the same forward-compatibility
        /// reason as `bestUCI`: older persisted `SavedGame` data decodes as nil.
        public var fen: String?
        public init(moveNumber: Int, san: String, classification: String,
                    winBefore: Double, winAfter: Double, betterSan: String?,
                    bestUCI: String? = nil, fen: String? = nil) {
            self.moveNumber = moveNumber; self.san = san; self.classification = classification
            self.winBefore = winBefore; self.winAfter = winAfter; self.betterSan = betterSan
            self.bestUCI = bestUCI; self.fen = fen
        }
    }
}
