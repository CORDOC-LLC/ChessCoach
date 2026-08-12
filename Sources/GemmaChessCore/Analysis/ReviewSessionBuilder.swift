//  ReviewSessionBuilder.swift
//  Builds a full `ReviewSession` (the win-graph + played-vs-best timeline
//  `ReviewScreen` shows) straight from a Play-mode `SavedGame`'s already-
//  captured live data -- zero Stockfish calls. `GameAnalyzer.analyzeGame`
//  computes the exact same shape by re-sweeping a PGN with the engine; this is
//  the free path for a game whose live per-ply data (`SavedGame.
//  winAfterMover`) already covers everything that sweep would recompute.
//
//  Not every saved game qualifies -- see `canBuild(from:)`. Callers fall back
//  to `GameAnalyzer.analyzeGame` (via `ReviewViewModel.analyze`, which already
//  checks `AnalysisCache` first) for anything that doesn't.

import Foundation

public enum ReviewSessionBuilder {

    /// Whether `savedGame` has everything needed to build a full session with
    /// zero re-analysis: `winAfterMover` covering every ply, and at least two
    /// plies played (nothing meaningful to review otherwise). A saved game
    /// from before `winAfterMover` existed, or one where a live capture raced
    /// an undo or hit an engine hiccup for even a single ply (see the
    /// append-site guards in `PlayViewModel.tap(_:)`/`engineReply`'s caller),
    /// doesn't qualify -- that's by design: a partially-filled array is
    /// treated as fully unavailable rather than silently building a session
    /// with a gap in its win-graph.
    public static func canBuild(from savedGame: SavedGame) -> Bool {
        guard savedGame.moves.count >= 2 else { return false }
        return savedGame.winAfterMover?.count == savedGame.moves.count
    }

    /// Build the session. Returns nil whenever `canBuild` would return false.
    public static func build(from savedGame: SavedGame) -> ReviewSession? {
        guard canBuild(from: savedGame), let winAfterMover = savedGame.winAfterMover else { return nil }

        let plyCount = savedGame.moves.count
        let side = savedGame.playerIsWhite ? "white" : "black"
        let (result, _) = HistoryStore.playResult(
            text: savedGame.resultText, playerIsWhite: savedGame.playerIsWhite)
        let pgn = HistoryStore.pgn(from: savedGame, result: result)

        var headers = [
            "White": savedGame.playerIsWhite ? "Me" : "Stockfish",
            "Black": savedGame.playerIsWhite ? "Stockfish" : "Me",
            "Result": result,
        ]
        if let opening = savedGame.openingName, !opening.isEmpty { headers["Opening"] = opening }
        if let eco = savedGame.openingECO, !eco.isEmpty { headers["ECO"] = eco }

        // Mover-relative winBefore at ply i is the PREVIOUS ply's winAfter,
        // perspective-flipped (100 - x) since the mover alternates every ply --
        // exact, not approximate, since both values describe the identical
        // position (`winAfterMover[i-1]` IS `fenHistory[i]`'s evaluation, just
        // captured from the other side's perspective). Ply 0 has no previous
        // ply; 50.0 is the textbook standard-starting-position estimate, used
        // consistently below for the timeline's node 0 too.
        func winBefore(atPly i: Int) -> Double {
            i == 0 ? 50.0 : (100.0 - winAfterMover[i - 1])
        }

        // Every ply the reviewed side (`savedGame.playerIsWhite`) played, in
        // order, zipped against `moveRecords` -- mirrors the same pairing
        // `HistoryStore.buildGameRecord(from savedGame:)` already relies on
        // (moveRecords holds only the user's plies, in play order, with
        // neither its own UCI nor ply index -- position is the only link).
        let userPlyIndices = (0..<plyCount).filter { ($0 % 2 == 0) == savedGame.playerIsWhite }
        var recordByPly: [Int: CoachPromptBuilder.PlayMoveRecord] = [:]
        for (idx, record) in zip(userPlyIndices, savedGame.moveRecords) {
            // Guard against a mid-grade rewind having desynced records from
            // plies (same check `PlayViewModel.verdict(forPly:)` applies).
            guard savedGame.sanMoves.indices.contains(idx), savedGame.sanMoves[idx] == record.san else { continue }
            recordByPly[idx] = record
        }

        var whiteAccs: [Double] = []
        var blackAccs: [Double] = []
        var allMoves: [MoveReview] = []

        for i in 0..<plyCount {
            let isWhiteMove = i % 2 == 0
            let wb = winBefore(atPly: i)
            let wa = winAfterMover[i]
            let acc = Evaluation.moveAccuracy(winBefore: wb, winAfter: wa)
            if isWhiteMove { whiteAccs.append(acc) } else { blackAccs.append(acc) }

            // Only the reviewed side's mistakes/moves feed `allMoves`, matching
            // GameAnalyzer's own "only review my moves" contract.
            guard let record = recordByPly[i] else { continue }
            let fenBefore = savedGame.fenHistory[i]
            let fenAfter = record.fen ?? (savedGame.fenHistory.indices.contains(i + 1) ? savedGame.fenHistory[i + 1] : fenBefore)
            let bestSAN = record.bestUCI.flatMap { ChessLogic.san(fromUCI: $0, inFEN: fenBefore) } ?? record.betterSan
            var comment = ""
            if ["inaccuracy", "mistake", "blunder"].contains(record.classification) {
                // Simpler than GameAnalyzer's mistakeComment -- no stored PV
                // beyond the single best move, so no "then <line>" follow-up.
                comment = "Win chance \(Self.fmt1(wb))% → \(Self.fmt1(wa))%."
                if let better = bestSAN { comment += " Better was \(better)." }
            }
            allMoves.append(MoveReview(
                ply: i + 1, moveNumber: (i / 2) + 1, color: isWhiteMove ? "white" : "black",
                moveSAN: record.san, moveUCI: savedGame.moves[i],
                fenBefore: fenBefore, fenAfter: fenAfter,
                // Centipawns were never captured live -- only win% was (see
                // SavedGame.winAfterMover). Neither is read by ReviewScreen's
                // UI (confirmed: only winBefore/winAfter/classification/
                // bestMoveSAN/comment are), so 0 here costs nothing real.
                evalBefore: 0, evalAfter: 0,
                winBefore: Evaluation.round1(wb), winAfter: Evaluation.round1(wa),
                winSwing: Evaluation.round1(wb - wa),
                classification: record.classification,
                bestMoveSAN: bestSAN ?? record.san,
                bestLineUCI: record.bestUCI.map { [$0] } ?? [],
                bestLineSAN: bestSAN.map { [$0] } ?? [],
                accuracy: Evaluation.round1(acc), comment: comment,
                clockAfter: nil, oppClock: nil
            ))
        }

        let mistakes = allMoves.filter { ["inaccuracy", "mistake", "blunder"].contains($0.classification) }
        var mistakeIndexByPly: [Int: Int] = [:]
        for (idx, m) in mistakes.enumerated() { mistakeIndexByPly[m.ply] = idx }

        // Timeline: one node per position, 0...plyCount -- mirrors
        // GameAnalyzer.buildTimeline's shape exactly, just reading captured
        // data instead of a fresh `posEvals` sweep.
        var timeline: [TimelineNode] = []
        for k in 0...plyCount {
            let isFinal = k == plyCount
            let fen = savedGame.fenHistory[k]
            let turnIsWhite = k % 2 == 0   // White always moves first from a standard start
            let winWhiteAtNode: Double
            if k == 0 {
                winWhiteAtNode = 50.0
            } else {
                let priorMoverIsWhite = (k - 1) % 2 == 0
                winWhiteAtNode = priorMoverIsWhite ? winAfterMover[k - 1] : (100.0 - winAfterMover[k - 1])
            }
            var node = TimelineNode(
                node: k, fen: fen, winWhite: Evaluation.round1(winWhiteAtNode),
                color: turnIsWhite ? "white" : "black", moveNumber: (k / 2) + 1
            )
            if !isFinal {
                let ply = k + 1
                node.ply = ply
                node.moveSAN = savedGame.sanMoves[k]
                node.moveUCI = savedGame.moves[k]
                if let record = recordByPly[k] {
                    node.bestUCI = record.bestUCI
                    node.bestSAN = record.bestUCI.flatMap { ChessLogic.san(fromUCI: $0, inFEN: fen) } ?? record.betterSan
                    node.isMyMove = true
                    node.classification = record.classification
                    node.mistakeIndex = mistakeIndexByPly[ply]
                } else {
                    node.isMyMove = false
                }
            }
            timeline.append(node)
        }

        return ReviewSession(
            pgn: pgn, player: side, headers: headers, result: result,
            speed: Speed.unknown.rawValue,
            accuracyWhite: Evaluation.round1(Evaluation.aggregateAccuracy(whiteAccs)),
            accuracyBlack: Evaluation.round1(Evaluation.aggregateAccuracy(blackAccs)),
            allMoves: allMoves, mistakes: mistakes, currentIndex: 0,
            timeline: timeline
        )
    }

    private static func fmt1(_ x: Double) -> String {
        let rounded = Evaluation.round1(x)
        return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(rounded)
    }
}
