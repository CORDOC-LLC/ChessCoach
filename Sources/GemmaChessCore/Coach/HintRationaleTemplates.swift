//  HintRationaleTemplates.swift
//  U3 — free, template-based "why" rationale for the on-demand hint. Distinct from
//  `Motifs.swift`: that file tags mistakes ALREADY made (backward-looking, compares a
//  played move to the best move). This classifies the RECOMMENDED move BEFORE it's
//  played (forward-looking), reusing the same low-level, engine-free primitives
//  (`BoardAttacks.parseUCI`, `.value`, hanging-piece detection) for a different job.
//
//  No LLM, no network call: everything here runs on facts `PlayViewModel.requestHint`
//  already has in hand (the position, the recommended move, and the mate distance the
//  engine already reported for that position), so the rationale is available
//  synchronously, in the same tick as the hint's arrows/SAN, regardless of Pro status.

import Foundation
import ChessKit

/// Classifies the engine's recommended move into a short, human-readable "why" —
/// a free-tier counterpart to the Pro coach's richer streamed rationale.
public enum HintRationaleTemplates {

    private static let pieceNames: [Piece.Kind: String] = [
        .pawn: "pawn", .knight: "knight", .bishop: "bishop",
        .rook: "rook", .queen: "queen", .king: "king",
    ]

    /// Generic fallback for quiet developing/positional moves, or when the move/FEN
    /// can't be parsed. Never returns an empty string.
    private static let genericTemplate = "A solid move that improves the position."

    /// One-line, engine-free "why" for the recommended move.
    ///
    /// - Parameters:
    ///   - fenBefore: The position before the recommended move.
    ///   - moveUCI: The recommended move, in UCI form (e.g. "g1f3").
    ///   - mateIn: The number of moves to forced mate for the side to move in
    ///     `fenBefore`, if the engine already found one (e.g. parsed from
    ///     `EngineLineReport.eval`'s "#N" form). Pass `nil` when no mate is known.
    ///
    /// Priority when a move matches more than one classification (documented choice,
    /// not incidental): **forced mate > material capture > defensive (escapes a
    /// threat) > generic fallback**. Mate wins because it ends the game outright,
    /// which dominates any other reason the move is good; a capture beats "defensive"
    /// because winning material is the more concrete, independently checkable claim.
    ///
    /// Never crashes on malformed/unparseable UCI or FEN — falls back to the generic
    /// template.
    public static func rationale(fenBefore: String, moveUCI: String, mateIn: Int? = nil) -> String {
        guard let move = BoardAttacks.parseUCI(moveUCI), let board = Position(fen: fenBefore) else {
            return genericTemplate
        }

        if let mateIn, mateIn > 0 {
            return mateIn == 1 ? "Delivers checkmate." : "Sets up a forced mate in \(mateIn)."
        }

        if let capturedName = capturedPieceName(board: board, fenBefore: fenBefore, move: move) {
            return "Wins a \(capturedName)."
        }

        if isDefensive(board: board, fenBefore: fenBefore, moveUCI: moveUCI, move: move) {
            return "Gets a piece out of danger."
        }

        return genericTemplate
    }

    /// Parses a mate distance out of an `EngineLine.evalStr`-style string ("#3" for
    /// a mate the side to move delivers, "#-3" for a mate suffered) — only the
    /// former is a reason to praise the move, so a negative mate returns `nil`.
    public static func mateIn(fromEval eval: String) -> Int? {
        guard eval.hasPrefix("#"), !eval.hasPrefix("#-") else { return nil }
        return Int(eval.dropFirst())
    }

    // MARK: - Private classification

    /// The name of the piece the move captures, including en passant, or `nil` if
    /// the move isn't a capture.
    private static func capturedPieceName(
        board: Position, fenBefore: String, move: (from: Square, to: Square, promo: Piece.Kind?)
    ) -> String? {
        if let captured = board.piece(at: move.to) {
            return pieceNames[captured.kind] ?? "piece"
        }
        // En passant: a pawn moving diagonally onto an empty square.
        guard let mover = board.piece(at: move.from), mover.kind == .pawn,
              BoardAttacks.file(move.from) != BoardAttacks.file(move.to) else { return nil }
        let epTarget = enPassantTarget(fenBefore)
        return move.to == epTarget ? "pawn" : nil
    }

    /// True when the moving piece was hanging (en prise) before the move, and the
    /// move takes it somewhere the same simple hanging-check no longer flags — i.e.
    /// it escapes the threat rather than just relocating it. Reuses the same
    /// hanging-piece definition `Motifs.isHanging` uses, applied to the FROM square
    /// (a threat the recommended move is escaping) rather than the TO square (what
    /// Motifs checks, after a mistake has already happened).
    private static func isDefensive(
        board: Position, fenBefore: String, moveUCI: String,
        move: (from: Square, to: Square, promo: Piece.Kind?)
    ) -> Bool {
        guard let piece = board.piece(at: move.from), isHanging(board, square: move.from) else {
            return false
        }
        guard let afterFEN = ChessLogic.fen(afterMove: moveUCI, fromFEN: fenBefore),
              let after = Position(fen: afterFEN) else {
            return true   // can't verify further; the escape attempt itself is the signal
        }
        return !isHanging(after, square: move.to, movedPiece: piece)
    }

    /// Static SEE-lite: is the piece on `square` left en prise (undefended, or won by
    /// a cheaper attacker)? Same shape as `Motifs`' private helper of the same name.
    private static func isHanging(_ position: Position, square: Square, movedPiece: Piece? = nil) -> Bool {
        guard let piece = movedPiece ?? position.piece(at: square) else { return false }
        let attackers = BoardAttacks.attackers(of: piece.color.opposite, on: square, in: position)
        if attackers.isEmpty { return false }
        let defenders = BoardAttacks.attackers(of: piece.color, on: square, in: position)
        let cheapest = attackers.map { BoardAttacks.value(position.piece(at: $0)) }.min() ?? 0
        return defenders.isEmpty || cheapest < BoardAttacks.value(piece)
    }

    private static func enPassantTarget(_ fen: String) -> Square? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return nil }
        let ep = String(fields[3])
        return ep == "-" ? nil : Square(ep)
    }
}
