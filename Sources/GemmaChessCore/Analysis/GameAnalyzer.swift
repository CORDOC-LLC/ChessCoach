//  GameAnalyzer.swift
//  U7 — full-game sweep. Port of the source project's `server/core/game_analysis.py`.
//
//  We analyse every position along the mainline exactly once (EnginePool caches the
//  evals), then derive each move's before/after win% from consecutive positions:
//
//      win_before(my move at P)  = best win% at P            (I am to move at P)
//      win_after (my move at P)  = 100 - best win% at P+1    (opponent is to move at P+1)
//
//  Terminal positions are scored WITHOUT the engine: checkmate -> side-to-move lost
//  (win 0, cp -mate); stalemate -> 50/0. Draws by repetition / 50-move rule are not
//  detected here (ChessLogic.status only reports checkmate/stalemate) so they fall
//  through to the engine — best-effort, out of scope, matching the unit's note.

import Foundation
import ChessKit

/// Full review of a single one of *my* moves. Mirrors session.py's `MoveReview`.
public struct MoveReview: Codable, Sendable, Equatable {
    public var ply: Int           // 1-based half-move number in the game
    public var moveNumber: Int    // full-move number (e.g. 4 for "4. Nf3")
    public var color: String      // "white" | "black" (whose move this is)
    public var moveSAN: String
    public var moveUCI: String
    public var fenBefore: String
    public var fenAfter: String
    public var evalBefore: Double // centipawns from my perspective (best available), mate -> +/-MATE
    public var evalAfter: Double  // centipawns from my perspective after my move
    public var winBefore: Double  // win% from my perspective (best available)
    public var winAfter: Double   // win% from my perspective after my move
    public var winSwing: Double   // win_before - win_after (>=0 means I lost ground)
    public var classification: String
    public var bestMoveSAN: String
    public var bestLineUCI: [String]
    public var bestLineSAN: [String]
    public var accuracy: Double
    public var comment: String    // engine-grounded prose explanation (mistakes only)
    public var clockAfter: Double?  // my remaining time after this move (from [%clk]), nil if none
    public var oppClock: Double?    // opponent's remaining at their previous move

    public init(
        ply: Int, moveNumber: Int, color: String, moveSAN: String, moveUCI: String,
        fenBefore: String, fenAfter: String, evalBefore: Double, evalAfter: Double,
        winBefore: Double, winAfter: Double, winSwing: Double, classification: String,
        bestMoveSAN: String, bestLineUCI: [String], bestLineSAN: [String], accuracy: Double,
        comment: String = "", clockAfter: Double? = nil, oppClock: Double? = nil
    ) {
        self.ply = ply; self.moveNumber = moveNumber; self.color = color
        self.moveSAN = moveSAN; self.moveUCI = moveUCI
        self.fenBefore = fenBefore; self.fenAfter = fenAfter
        self.evalBefore = evalBefore; self.evalAfter = evalAfter
        self.winBefore = winBefore; self.winAfter = winAfter; self.winSwing = winSwing
        self.classification = classification
        self.bestMoveSAN = bestMoveSAN; self.bestLineUCI = bestLineUCI; self.bestLineSAN = bestLineSAN
        self.accuracy = accuracy; self.comment = comment
        self.clockAfter = clockAfter; self.oppClock = oppClock
    }
}

/// Errors from the analysis layer.
public struct AnalysisError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Full-game analysis sweep -> `ReviewSession`.
public enum GameAnalyzer {

    /// Evaluation of a single position, from the side-to-move's perspective.
    struct PosEval {
        var winStm: Double          // win% for the side to move
        var cpStm: Double           // signed centipawns for the side to move (mate -> +/-MATE)
        var bestPvUCI: [String]     // principal variation (empty if terminal)
        var isTerminal: Bool
    }

    /// One walked mainline ply.
    struct Step {
        var fenBefore: String
        var fenAfter: String
        var moveUCI: String
        var moveSAN: String
        var moveNumber: Int
        var moverIsWhite: Bool
        var clock: Double?
    }

    // Lichess ratings run higher than chess.com / FIDE; pull them to a common scale.
    static let eloOffsets: [String: Int] = ["lichess": -200, "chesscom": 0]
    static let sensitivityElo: [String: Double] = [
        "casual": 1000.0, "default": 1500.0, "strong": 2000.0, "master": 2400.0,
    ]

    /// Analyse a PGN and build a `ReviewSession` for `player`'s mistakes.
    ///
    /// `onProgress(done, total)` is called after each position is evaluated (best-effort).
    public static func analyzeGame(
        pgn: String,
        player: String = "auto",
        depth: Int? = nil,
        elo: Int? = nil,
        sensitivity: String? = nil,
        username: String = "",
        aliases: [String] = [],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ReviewSession {
        let headers = MultiPGN.headers(ofPGN: pgn)
        let me = resolvePlayer(headers: headers, player: player, username: username, aliases: aliases)
        let myColorIsWhite = (me == "white")

        let (reviewElo, eloSource) = resolveReviewElo(
            headers: headers, me: me, elo: elo, sensitivity: sensitivity)
        let speed = Evaluation.classifySpeed(timeControl: headers["TimeControl"], event: headers["Event"])
        // Cutoffs adapt to BOTH skill (Elo) and mode.
        let thresholds = Evaluation.thresholdsForSpeed(Evaluation.thresholdsForElo(reviewElo), speed: speed)
        let useDepth = depth ?? depthForElo(reviewElo)

        // Replay the mainline, collecting (fenBefore, move, clock) per ply + the final FEN.
        let (steps, finalFEN) = try walkMainline(pgn: pgn)

        // Evaluate every position once (the slow part of the sweep), reporting progress.
        var posEvals: [PosEval] = []
        let total = steps.count + 1
        func report(_ done: Int) { onProgress?(done, total) }
        for step in steps {
            posEvals.append(try await evaluatePosition(fen: step.fenBefore, depth: useDepth))
            report(posEvals.count)
        }
        posEvals.append(try await evaluatePosition(fen: finalFEN, depth: useDepth))
        report(posEvals.count)

        var allMyMoves: [MoveReview] = []
        var whiteAccs: [Double] = []
        var blackAccs: [Double] = []

        for (i, step) in steps.enumerated() {
            let moverIsWhite = step.moverIsWhite
            let evalAt = posEvals[i]
            let evalNext = posEvals[i + 1]

            let winBefore = evalAt.winStm
            let winAfter = 100.0 - evalNext.winStm
            let cpBefore = evalAt.cpStm
            let cpAfter = -evalNext.cpStm
            let acc = Evaluation.moveAccuracy(winBefore: winBefore, winAfter: winAfter)

            if moverIsWhite { whiteAccs.append(acc) } else { blackAccs.append(acc) }

            if moverIsWhite != myColorIsWhite { continue }  // only review my moves

            let bestUCI = evalAt.bestPvUCI.first ?? step.moveUCI
            let isBest = step.moveUCI == bestUCI
            let classification = Evaluation.classify(
                winBefore: winBefore, winAfter: winAfter, isBest: isBest, thresholds: thresholds
            ).rawValue

            let bestLineSAN = ChessLogic.pvToSAN(evalAt.bestPvUCI, fromFEN: step.fenBefore)
            let bestMoveSAN = bestLineSAN.first ?? step.moveSAN

            var comment = ""
            if classification == "inaccuracy" || classification == "mistake" || classification == "blunder" {
                let followupSAN = ChessLogic.pvToSAN(evalNext.bestPvUCI, fromFEN: step.fenAfter, maxMoves: 6)
                comment = mistakeComment(
                    winBefore: round1(winBefore), winAfter: round1(winAfter),
                    bestMoveSAN: bestMoveSAN, bestLineSAN: bestLineSAN, followupSAN: followupSAN)
            }

            allMyMoves.append(MoveReview(
                ply: i + 1,
                moveNumber: step.moveNumber,
                color: moverIsWhite ? "white" : "black",
                moveSAN: step.moveSAN,
                moveUCI: step.moveUCI,
                fenBefore: step.fenBefore,
                fenAfter: step.fenAfter,
                evalBefore: round1(cpBefore),
                evalAfter: round1(cpAfter),
                winBefore: round1(winBefore),
                winAfter: round1(winAfter),
                winSwing: round1(winBefore - winAfter),
                classification: classification,
                bestMoveSAN: bestMoveSAN,
                bestLineUCI: Array(evalAt.bestPvUCI.prefix(12)),
                bestLineSAN: bestLineSAN,
                accuracy: round1(acc),
                comment: comment,
                clockAfter: step.clock,
                oppClock: i >= 1 ? steps[i - 1].clock : nil
            ))
        }

        let mistakes = allMyMoves.filter {
            $0.classification == "inaccuracy" || $0.classification == "mistake" || $0.classification == "blunder"
        }

        let timeline = buildTimeline(
            steps: steps, posEvals: posEvals, finalFEN: finalFEN,
            allMyMoves: allMyMoves, mistakes: mistakes, myColorIsWhite: myColorIsWhite)

        return ReviewSession(
            pgn: pgn,
            player: me,
            headers: headers,
            result: headers["Result"] ?? "*",
            speed: speed.rawValue,
            accuracyWhite: round1(Evaluation.aggregateAccuracy(whiteAccs)),
            accuracyBlack: round1(Evaluation.aggregateAccuracy(blackAccs)),
            allMoves: allMyMoves,
            mistakes: mistakes,
            currentIndex: 0,
            exploreFen: nil,
            coachAiText: nil,
            reviewElo: reviewElo,
            eloSource: eloSource,
            thresholds: [thresholds.inaccuracy, thresholds.mistake, thresholds.blunder],
            sweepDepth: useDepth,
            timeline: timeline
        )
    }

    // MARK: Position evaluation

    /// Evaluate `fen` from the side-to-move's perspective, handling terminal cases.
    static func evaluatePosition(fen: String, depth: Int) async throws -> PosEval {
        switch ChessLogic.status(forFEN: fen) {
        case .checkmate:
            // The side to move is checkmated -> losing.
            return PosEval(winStm: 0.0, cpStm: Double(-GCConfig.mateScoreCp), bestPvUCI: [], isTerminal: true)
        case .stalemate:
            return PosEval(winStm: 50.0, cpStm: 0.0, bestPvUCI: [], isTerminal: true)
        default:
            let best = try await EnginePool.shared.analyse(fen: fen, depth: depth, multipv: 1).best
            return PosEval(
                winStm: best.winPercent, cpStm: best.signedCp,
                bestPvUCI: best.pvUCI, isTerminal: false)
        }
    }

    // MARK: Timeline

    /// Win% from White's perspective, given whose move it is at that position.
    static func winWhite(_ pe: PosEval, turnIsWhite: Bool) -> Double {
        turnIsWhite ? pe.winStm : 100.0 - pe.winStm
    }

    static func buildTimeline(
        steps: [Step], posEvals: [PosEval], finalFEN: String,
        allMyMoves: [MoveReview], mistakes: [MoveReview], myColorIsWhite: Bool
    ) -> [TimelineNode] {
        var clsByPly: [Int: String] = [:]
        for m in allMyMoves { clsByPly[m.ply] = m.classification }
        var mistakeIndexByPly: [Int: Int] = [:]
        for (i, m) in mistakes.enumerated() { mistakeIndexByPly[m.ply] = i }

        var nodes: [TimelineNode] = []
        for k in 0...steps.count {
            let isFinal = k == steps.count
            let fen = isFinal ? finalFEN : steps[k].fenBefore
            let turnIsWhite = ChessLogic.sideToMove(forFEN: fen) == .white
            var node = TimelineNode(
                node: k,
                fen: fen,
                winWhite: round1(winWhite(posEvals[k], turnIsWhite: turnIsWhite)),
                color: turnIsWhite ? "white" : "black",
                moveNumber: fullmoveNumber(fromFEN: fen)
            )
            if !isFinal {
                let step = steps[k]
                let evalAt = posEvals[k]
                let bestUCI = evalAt.bestPvUCI.first
                let ply = k + 1
                node.ply = ply
                node.moveSAN = step.moveSAN
                node.moveUCI = step.moveUCI
                node.bestUCI = bestUCI
                node.bestSAN = bestUCI.flatMap { ChessLogic.san(fromUCI: $0, inFEN: fen) }
                node.isMyMove = step.moverIsWhite == myColorIsWhite
                node.classification = clsByPly[ply]
                node.mistakeIndex = mistakeIndexByPly[ply]
            }
            nodes.append(node)
        }
        return nodes
    }

    // MARK: Mistake comment

    /// Concrete written explanation of a mistake, stitched from engine data we already have.
    static func mistakeComment(
        winBefore: Double, winAfter: Double,
        bestMoveSAN: String, bestLineSAN: [String], followupSAN: [String]
    ) -> String {
        var parts = ["Win chance \(fmt(winBefore))% → \(fmt(winAfter))%."]
        if !bestMoveSAN.isEmpty {
            let cont = bestLineSAN.dropFirst().prefix(4).joined(separator: " ")
            parts.append("Better was \(bestMoveSAN)" + (cont.isEmpty ? "." : ", then \(cont)."))
        }
        if !followupSAN.isEmpty {
            parts.append("Played line: \(followupSAN.joined(separator: " ")).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Player / Elo resolution

    /// Resolve player="white"|"black"|"auto" to a concrete color.
    static func resolvePlayer(headers: [String: String], player: String, username: String, aliases: [String]) -> String {
        let p = (player.isEmpty ? "auto" : player).lowercased()
        if p == "white" || p == "black" { return p }
        var mine = Set<String>()
        mine.insert(username.lowercased().trimmingCharacters(in: .whitespaces))
        for a in aliases { mine.insert(a.lowercased().trimmingCharacters(in: .whitespaces)) }
        mine.remove("")
        let white = (headers["White"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let black = (headers["Black"] ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if mine.contains(white) { return "white" }
        if mine.contains(black) { return "black" }
        return "white"
    }

    static func detectPlatform(_ headers: [String: String]) -> String? {
        let blob = ["Site", "Link", "Event"].map { headers[$0] ?? "" }.joined(separator: " ").lowercased()
        if blob.contains("lichess") { return "lichess" }
        if blob.contains("chess.com") || blob.contains("chesscom") { return "chesscom" }
        return nil
    }

    /// Resolve the normalized review Elo + where it came from.
    /// Priority: explicit `elo` > named `sensitivity` > PGN WhiteElo/BlackElo (platform-normalized) > nil.
    static func resolveReviewElo(
        headers: [String: String], me: String, elo: Int?, sensitivity: String?
    ) -> (Double?, String?) {
        if let elo { return (Double(elo), "explicit") }
        if let s = sensitivity?.lowercased(), let v = sensitivityElo[s] {
            return (v, "sensitivity:\(s)")
        }
        let raw = (headers[me == "white" ? "WhiteElo" : "BlackElo"] ?? "").trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty, raw.allSatisfy(\.isNumber), let n = Int(raw) {
            let platform = detectPlatform(headers)
            return (Double(n + (eloOffsets[platform ?? ""] ?? 0)), platform ?? "pgn")
        }
        return (nil, nil)
    }

    /// Deepen the sweep for stronger players so small win%-drop cutoffs aren't just noise.
    static func depthForElo(_ elo: Double?) -> Int {
        let base = GCConfig.sweepDepth
        guard let elo else { return base }
        if elo >= 2300 { return max(base, 20) }
        if elo >= 1900 { return max(base, 18) }
        return base
    }

    // MARK: Mainline walking

    /// Replay the PGN mainline, returning each ply's (fenBefore, fenAfter, move, clock) plus
    /// the final FEN. FENs are reconstructed through `ChessLogic.fen(afterMove:)` from the
    /// starting position, keeping the whole sweep on the same FEN/SAN path the rest of the
    /// core uses. Per-ply clocks come from each move's `[%clk H:MM:SS]` comment.
    static func walkMainline(pgn: String) throws -> (steps: [Step], finalFEN: String) {
        guard let parsed = try? Game(pgn: pgn) else {
            throw AnalysisError("Could not parse a game from the provided PGN.")
        }
        let mainline = parsed.moves.indices
            .filter { $0.variation == MoveTree.Index.mainVariation }
            .sorted()

        let standardStart = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        var curFEN = parsed.startingPosition?.fen ?? standardStart
        var steps: [Step] = []

        for idx in mainline {
            guard let move = parsed.moves[idx] else { continue }
            let uci = move.lan
            let fenBefore = curFEN
            guard let fenAfter = ChessLogic.fen(afterMove: uci, fromFEN: fenBefore) else { break }
            let san = ChessLogic.san(fromUCI: uci, inFEN: fenBefore) ?? move.san
            steps.append(Step(
                fenBefore: fenBefore,
                fenAfter: fenAfter,
                moveUCI: uci,
                moveSAN: san,
                moveNumber: fullmoveNumber(fromFEN: fenBefore),
                moverIsWhite: idx.color == .white,
                clock: clockSeconds(fromComment: move.comment)
            ))
            curFEN = fenAfter
        }
        return (steps, curFEN)
    }

    // MARK: Helpers

    static func round1(_ x: Double) -> Double { Evaluation.round1(x) }

    /// Format a (already 1-dp-rounded) double the way Python's f-string renders it.
    static func fmt(_ x: Double) -> String {
        if x == x.rounded() { return String(format: "%.1f", x) }
        return String(x)
    }

    static func fullmoveNumber(fromFEN fen: String) -> Int {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 6, let n = Int(fields[5]) else { return 1 }
        return n
    }

    /// Remaining seconds from a `[%clk H:MM:SS(.s)]` move comment, or nil.
    static func clockSeconds(fromComment comment: String) -> Double? {
        guard let range = comment.range(of: #"\[%clk\s+([0-9:.]+)\]"#, options: .regularExpression) else {
            return nil
        }
        // Extract the time token between "clk" and "]".
        let chunk = String(comment[range])
        guard let timeRange = chunk.range(of: #"[0-9]+:[0-9]+:[0-9.]+|[0-9]+:[0-9.]+|[0-9.]+"#, options: .regularExpression) else {
            return nil
        }
        let token = String(chunk[timeRange])
        let parts = token.split(separator: ":").map { Double($0) ?? 0 }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return nil
        }
    }
}
