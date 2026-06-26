//  ReviewSession.swift
//  U8 — session model. Port of the state in the source's `server/core/session.py`.
//
//  Everything about one analysed game: the per-side accuracies, the reviewed side's
//  ordered mistakes, and a per-node timeline of the whole game (both sides) that powers
//  the win graph and board navigation.

import Foundation

/// One entry per position (node 0..N) in the timeline. Non-final nodes carry their
/// OUTGOING move, the engine's best move there, and (for the player's moves) the
/// classification + mistake link. Mirrors `_build_timeline`'s per-node dict.
public struct TimelineNode: Codable, Sendable, Equatable {
    public var node: Int
    public var fen: String
    public var winWhite: Double      // win% from White's perspective at this position
    public var color: String         // side to move: "white" | "black"
    public var moveNumber: Int

    // Non-final nodes only.
    public var ply: Int?
    public var moveSAN: String?
    public var moveUCI: String?
    public var bestUCI: String?
    public var bestSAN: String?
    public var isMyMove: Bool?
    public var classification: String?
    public var mistakeIndex: Int?

    public init(
        node: Int, fen: String, winWhite: Double, color: String, moveNumber: Int,
        ply: Int? = nil, moveSAN: String? = nil, moveUCI: String? = nil,
        bestUCI: String? = nil, bestSAN: String? = nil, isMyMove: Bool? = nil,
        classification: String? = nil, mistakeIndex: Int? = nil
    ) {
        self.node = node; self.fen = fen; self.winWhite = winWhite
        self.color = color; self.moveNumber = moveNumber
        self.ply = ply; self.moveSAN = moveSAN; self.moveUCI = moveUCI
        self.bestUCI = bestUCI; self.bestSAN = bestSAN; self.isMyMove = isMyMove
        self.classification = classification; self.mistakeIndex = mistakeIndex
    }
}

/// Everything about one analysed game. Mirrors session.py's `ReviewSession`.
public struct ReviewSession: Codable, Sendable, Equatable {
    public var pgn: String
    public var player: String                 // "white" | "black" — whose mistakes we reviewed
    public var headers: [String: String]
    public var result: String
    public var speed: String                  // bullet/blitz/rapid/classical/correspondence/unknown
    public var accuracyWhite: Double
    public var accuracyBlack: Double
    public var allMoves: [MoveReview]          // every move by `player`
    public var mistakes: [MoveReview]          // inaccuracy/mistake/blunder
    public var currentIndex: Int              // index into `mistakes`
    public var exploreFen: String?
    public var coachAiText: String?           // cached on-demand coaching summary
    public var reviewElo: Double?             // Elo the thresholds were tuned to (normalized)
    public var eloSource: String?
    public var thresholds: [Double]?          // (inaccuracy, mistake, blunder) win%-drop cutoffs
    public var sweepDepth: Int?
    public var timeline: [TimelineNode]

    public init(
        pgn: String,
        player: String,
        headers: [String: String] = [:],
        result: String = "*",
        speed: String = "unknown",
        accuracyWhite: Double = 100.0,
        accuracyBlack: Double = 100.0,
        allMoves: [MoveReview] = [],
        mistakes: [MoveReview] = [],
        currentIndex: Int = 0,
        exploreFen: String? = nil,
        coachAiText: String? = nil,
        reviewElo: Double? = nil,
        eloSource: String? = nil,
        thresholds: [Double]? = nil,
        sweepDepth: Int? = nil,
        timeline: [TimelineNode] = []
    ) {
        self.pgn = pgn; self.player = player; self.headers = headers
        self.result = result; self.speed = speed
        self.accuracyWhite = accuracyWhite; self.accuracyBlack = accuracyBlack
        self.allMoves = allMoves; self.mistakes = mistakes
        self.currentIndex = currentIndex; self.exploreFen = exploreFen
        self.coachAiText = coachAiText
        self.reviewElo = reviewElo; self.eloSource = eloSource
        self.thresholds = thresholds; self.sweepDepth = sweepDepth
        self.timeline = timeline
    }

    /// Display opening name: PGN `Opening` header if present, else a local lookup over the
    /// timeline FENs (so exports without opening tags still get named), else the bare `ECO`
    /// header, else "". Header-first keeps the platform's own labels authoritative.
    public func resolveOpening() -> String {
        let name = (headers["Opening"] ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let fens = timeline.map { $0.fen }
        if let classified = Openings.classifyFromFens(fens) {
            return classified.name
        }
        return (headers["ECO"] ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// Move the review cursor to mistake `index` and return the position before it.
    /// Returns nil (rather than throwing) on an out-of-range index or no mistakes.
    public mutating func gotoMistake(_ index: Int) -> (fenBefore: String, review: MoveReview)? {
        guard !mistakes.isEmpty, index >= 0, index < mistakes.count else { return nil }
        currentIndex = index
        exploreFen = nil
        let m = mistakes[index]
        return (m.fenBefore, m)
    }

    /// Compact, JSON-friendly summary of the session (mistakes + accuracy + opening + speed).
    public func summary() -> Summary {
        let items = mistakes.enumerated().map { (i, m) in
            Summary.Mistake(
                index: i,
                ply: m.ply,
                moveNumber: m.moveNumber,
                color: m.color,
                moveSAN: m.moveSAN,
                classification: m.classification,
                winSwing: m.winSwing,
                evalBefore: Self.round2(m.evalBefore / 100.0),
                evalAfter: Self.round2(m.evalAfter / 100.0),
                bestMoveSAN: m.bestMoveSAN,
                fenBefore: m.fenBefore,
                moveUCI: m.moveUCI,
                comment: m.comment,
                nodeIndex: m.ply - 1
            )
        }
        return Summary(
            result: result,
            player: player,
            white: headers["White"] ?? "?",
            black: headers["Black"] ?? "?",
            opening: resolveOpening(),
            speed: speed,
            timeControl: headers["TimeControl"],
            accuracyWhite: accuracyWhite,
            accuracyBlack: accuracyBlack,
            numMyMoves: allMoves.count,
            numMistakes: mistakes.count,
            currentIndex: currentIndex,
            reviewElo: reviewElo,
            eloSource: eloSource,
            thresholds: thresholds,
            sweepDepth: sweepDepth,
            mistakes: items
        )
    }

    /// Round to 2 decimals (round-half-to-even), matching Python's `round(x, 2)`.
    static func round2(_ x: Double) -> Double { (x * 100).rounded(.toNearestOrEven) / 100 }

    /// Compact summary payload returned by `summary()`.
    public struct Summary: Codable, Sendable, Equatable {
        public struct Mistake: Codable, Sendable, Equatable {
            public var index: Int
            public var ply: Int
            public var moveNumber: Int
            public var color: String
            public var moveSAN: String
            public var classification: String
            public var winSwing: Double
            public var evalBefore: Double   // in pawns (cp / 100)
            public var evalAfter: Double
            public var bestMoveSAN: String
            public var fenBefore: String
            public var moveUCI: String
            public var comment: String
            public var nodeIndex: Int
        }

        public var result: String
        public var player: String
        public var white: String
        public var black: String
        public var opening: String
        public var speed: String
        public var timeControl: String?
        public var accuracyWhite: Double
        public var accuracyBlack: Double
        public var numMyMoves: Int
        public var numMistakes: Int
        public var currentIndex: Int
        public var reviewElo: Double?
        public var eloSource: String?
        public var thresholds: [Double]?
        public var sweepDepth: Int?
        public var mistakes: [Mistake]
    }
}
