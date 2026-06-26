//  Motifs.swift
//  U9 — engine-free motif tagging. Port of `tag_motifs` (and helpers) from the
//  source `server/core/history.py`.
//
//  Cheap static heuristics (<= 2 ply of pure move-gen) over data we already have, so
//  history is essentially free to record and trivial to backfill when the heuristics
//  improve. Conservative on purpose — they run only on already-flagged mistakes, so a
//  true-positive bias is fine. All attack/defense maths is derived in `BoardAttacks`
//  since ChessKit doesn't publicly expose its bitboard attack tables.

import Foundation
import ChessKit

/// Static, engine-free motif tags for a single flagged move.
public enum Motifs {

    /// Human-readable labels for the coaching profile / chat injection.
    /// Mirrors the source `_MOTIF_LABELS`.
    public static let labels: [String: String] = [
        "hung_piece": "hanging pieces (leaving a piece en prise)",
        "pawn_grab": "greedy pawn-grabbing",
        "missed_capture": "missing free material",
        "missed_fork": "missing forks",
        "allowed_fork": "walking into forks",
        "allowed_mate": "allowing forced mate",
        "back_rank": "back-rank weaknesses",
        "missed_mate": "missing forced mates",
        "time_trouble": "blundering in time pressure (low clock)",
    ]

    /// Best-effort motif tags for one flagged move, from data we already have (no engine).
    ///
    /// Tags fall into three buckets: what we did wrong with our move (`pawn_grab`,
    /// `hung_piece`), what we missed (`missed_capture`, `missed_fork`, `missed_mate`),
    /// and what we let the opponent do (`allowed_fork`, `allowed_mate`, `back_rank`).
    public static func tagMotifs(
        fenBefore: String,
        moveUCI: String,
        bestUCI: String?,
        winSwing: Double,
        evalBefore: Double
    ) -> [String] {
        var motifs: [String] = []
        guard let board = Position(fen: fenBefore),
              let move = BoardAttacks.parseUCI(moveUCI) else { return motifs }

        // Is the played move legal in this position?
        let legal = ChessLogic.legalDestinations(forFEN: fenBefore)
        guard let tos = legal[move.from], tos.contains(move.to) else { return motifs }

        let mover = board.sideToMove
        let epTarget = enPassantTarget(fenBefore)

        // --- what we did with our move ---
        let movingPiece = board.piece(at: move.from)
        let captured = board.piece(at: move.to)
        let isEnPassant = movingPiece?.kind == .pawn && move.to == epTarget
            && BoardAttacks.file(move.from) != BoardAttacks.file(move.to) && captured == nil
        if captured != nil || isEnPassant {
            if isEnPassant || BoardAttacks.value(captured) == 1 {
                motifs.append("pawn_grab")
            }
        }

        // --- what we missed (the engine's best move) ---
        if let bestUCI, let best = BoardAttacks.parseUCI(bestUCI),
           bestUCI != moveUCI, let bTos = legal[best.from], bTos.contains(best.to) {
            let bestCapture = board.piece(at: best.to)
            let bestIsEP = board.piece(at: best.from)?.kind == .pawn && best.to == epTarget
                && BoardAttacks.file(best.from) != BoardAttacks.file(best.to) && bestCapture == nil
            if bestCapture != nil && !bestIsEP {
                if BoardAttacks.value(bestCapture) >= 3 { motifs.append("missed_capture") }
            }
            if isFork(fen: fenBefore, moveUCI: bestUCI) { motifs.append("missed_fork") }
        }

        // --- the position after our move (opponent to move) ---
        guard let afterFen = ChessLogic.fen(afterMove: moveUCI, fromFEN: fenBefore),
              let after = Position(fen: afterFen) else {
            appendMissedMate(&motifs, evalBefore: evalBefore)
            return motifs
        }

        if isHanging(after, square: move.to) { motifs.append("hung_piece") }

        let afterStatus = ChessLogic.status(forFEN: afterFen)
        let gameOver = afterStatus == .checkmate || afterStatus == .stalemate
        if !gameOver {
            if allowedOpponentFork(afterFen: afterFen) { motifs.append("allowed_fork") }
            if let mateMove = allowedMateInOne(afterFen: afterFen) {
                motifs.append("allowed_mate")
                if isBackRankMate(after, mateMove: mateMove, victim: mover) {
                    motifs.append("back_rank")
                }
            }
            if !motifs.contains("back_rank") && backRankWeak(after, color: mover) {
                motifs.append("back_rank")
            }
        }

        appendMissedMate(&motifs, evalBefore: evalBefore)
        return motifs
    }

    /// `time_trouble` when the move was made on a low clock, or far behind the opponent.
    /// Needs PGN `[%clk]` data; returns [] when clocks are absent. Port of `time_motifs`.
    public static func timeMotifs(
        clockAfter: Double?, oppClock: Double?, base: Double?
    ) -> [String] {
        guard let clockAfter else { return [] }
        let lowAbsolute = clockAfter <= 30 || (base != nil && clockAfter <= 0.10 * base!)
        let muchLessThanOpp = oppClock != nil && oppClock! > 0
            && clockAfter <= 0.5 * oppClock!
            && clockAfter <= (base != nil ? 0.20 * base! : 60)
        return (lowAbsolute || muchLessThanOpp) ? ["time_trouble"] : []
    }

    // MARK: - Private heuristics

    private static func appendMissedMate(_ motifs: inout [String], evalBefore: Double) {
        // A forced mate was available for the mover and we didn't play it.
        if evalBefore >= Double(GCConfig.mateScoreCp - 1000) {
            motifs.append("missed_mate")
        }
    }

    private static func enPassantTarget(_ fen: String) -> Square? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return nil }
        let ep = String(fields[3])
        return ep == "-" ? nil : Square(ep)
    }

    /// Static SEE-lite: is the piece on `square` left en prise (undefended, or won by a
    /// cheaper attacker)? `position` already has that piece on the board.
    private static func isHanging(_ position: Position, square: Square) -> Bool {
        guard let piece = position.piece(at: square) else { return false }
        let attackers = BoardAttacks.attackers(of: piece.color.opposite, on: square, in: position)
        if attackers.isEmpty { return false }
        let defenders = BoardAttacks.attackers(of: piece.color, on: square, in: position)
        let cheapest = attackers.map { BoardAttacks.value(position.piece(at: $0)) }.min() ?? 0
        return defenders.isEmpty || cheapest < BoardAttacks.value(piece)
    }

    /// Does `moveUCI` (by the side to move in `fen`) land a piece that forks >= 2
    /// valuable enemy targets? Port of `_is_fork`.
    private static func isFork(fen: String, moveUCI: String) -> Bool {
        guard let board = Position(fen: fen),
              let move = BoardAttacks.parseUCI(moveUCI) else { return false }
        let forker = board.sideToMove
        guard let afterFen = ChessLogic.fen(afterMove: moveUCI, fromFEN: fen),
              let b = Position(fen: afterFen),
              let pf = b.piece(at: move.to), pf.color == forker else { return false }

        let aVal = BoardAttacks.value(pf)
        let targets = BoardAttacks.attackSquares(of: pf, in: b).compactMap { sq -> (Square, Piece)? in
            guard let p = b.piece(at: sq), p.color != forker,
                  p.kind == .king || BoardAttacks.value(p) >= aVal else { return nil }
            return (sq, p)
        }
        if targets.count < 2 { return false }

        let givesCheck = targets.contains { $0.1.kind == .king }
        let undefended = targets.contains { (sq, p) in
            p.kind != .king && BoardAttacks.attackers(of: forker.opposite, on: sq, in: b).isEmpty
        }
        if !(givesCheck || undefended) { return false }

        // The forking piece must not just hang for free.
        let enemy = BoardAttacks.attackers(of: forker.opposite, on: move.to, in: b)
        if !enemy.isEmpty {
            let own = BoardAttacks.attackers(of: forker, on: move.to, in: b)
            let cheapest = enemy.map { BoardAttacks.value(b.piece(at: $0)) }.min() ?? 0
            if own.isEmpty && cheapest < aVal { return false }
        }
        return true
    }

    /// In the position after our move (opponent to move), can the opponent fork us?
    private static func allowedOpponentFork(afterFen: String) -> Bool {
        BoardAttacks.legalMovesUCI(fen: afterFen).contains { isFork(fen: afterFen, moveUCI: $0) }
    }

    /// The opponent's mate-in-1 in this position, if any (opponent to move).
    private static func allowedMateInOne(afterFen: String) -> (from: Square, to: Square, promo: Piece.Kind?)? {
        for uci in BoardAttacks.legalMovesUCI(fen: afterFen) {
            guard let nextFen = ChessLogic.fen(afterMove: uci, fromFEN: afterFen) else { continue }
            if ChessLogic.status(forFEN: nextFen) == .checkmate {
                return BoardAttacks.parseUCI(uci)
            }
        }
        return nil
    }

    /// Is `mateMove` a rook/queen mate delivered on `victim`'s back rank?
    private static func isBackRankMate(
        _ position: Position, mateMove: (from: Square, to: Square, promo: Piece.Kind?),
        victim: Piece.Color
    ) -> Bool {
        guard let piece = position.piece(at: mateMove.from),
              piece.kind == .rook || piece.kind == .queen else { return false }
        let back = victim == .white ? 0 : 7
        return BoardAttacks.rank(mateMove.to) == back
    }

    /// Structural back-rank weakness for `color`: king boxed on its back rank (no luft)
    /// while the opponent has a rook/queen on a file with no friendly pawn. Port of
    /// `_back_rank_weak`.
    private static func backRankWeak(_ position: Position, color: Piece.Color) -> Bool {
        guard let king = position.pieces.first(where: { $0.color == color && $0.kind == .king }) else {
            return false
        }
        let back = color == .white ? 0 : 7
        if BoardAttacks.rank(king.square) != back { return false }
        let forward = back + (color == .white ? 1 : -1)
        let kingFile = BoardAttacks.file(king.square)

        // No luft: every square in front of the king is occupied by one of the king's own pieces.
        for df in -1...1 {
            let f = kingFile + df
            if (0..<8).contains(f) {
                guard let sq = BoardAttacks.square(file: f, rank: forward),
                      let occ = position.piece(at: sq), occ.color == color else {
                    return false  // an escape square exists
                }
            }
        }

        let opp = color.opposite
        for piece in position.pieces where piece.color == opp
            && (piece.kind == .rook || piece.kind == .queen) {
            let f = BoardAttacks.file(piece.square)
            let hasFriendlyPawnOnFile = (0..<8).contains { r in
                guard let sq = BoardAttacks.square(file: f, rank: r),
                      let p = position.piece(at: sq) else { return false }
                return p.color == color && p.kind == .pawn
            }
            if !hasFriendlyPawnOnFile { return true }
        }
        return false
    }
}
