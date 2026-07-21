//  MoveCommentTemplates.swift
//  U3 — free, template-based one-line engine comment about the move JUST PLAYED
//  (the verdict prose for the unified Coach card). The backward-looking sibling of
//  `HintRationaleTemplates` (which explains the RECOMMENDED move before it's
//  played): this one judges a move after the fact, so it can use the position
//  after the move to see what the move actually cost or won.
//
//  No LLM, no network call: everything here runs on facts the play loop already
//  has in hand (`EngineLineReport.MoveReport` plus the two FENs), so the comment
//  is available synchronously with the verdict chip, regardless of Pro status.

import Foundation
import ChessKit

/// One-sentence, engine-free coach comment about the move just played —
/// a free-tier counterpart to the Pro coach's richer streamed note.
public enum MoveCommentTemplates {

    private static let pieceNames: [Piece.Kind: String] = [
        .pawn: "pawn", .knight: "knight", .bishop: "bishop",
        .rook: "rook", .queen: "queen", .king: "king",
    ]

    /// Generic fallback for quiet moves, or when the inputs can't be parsed.
    /// Never returns an empty string.
    private static let genericTemplate = "A reasonable move — keep building your position."

    /// One-line comment on the played move.
    ///
    /// - Parameters:
    ///   - fenBefore: The position before the move was played.
    ///   - fenAfter: The position after the move (side to move has flipped). Pass ""
    ///     if unknown — it's re-derived from `fenBefore` + `moveUCI` when possible.
    ///   - moveUCI: The played move in UCI form (e.g. "g1f3").
    ///   - moveSAN: The played move in SAN form (display only; "" is fine).
    ///   - classification: `Evaluation.Classification.rawValue` — one of
    ///     "best"/"good"/"inaccuracy"/"mistake"/"blunder" (case-insensitive).
    ///   - betterMoveSAN: The engine's preferred move when the played one wasn't it
    ///     (`EngineLineReport.MoveReport.betterMoveSAN`).
    ///   - evalAfter: `EngineLineReport.MoveReport.evalAfter` — the eval after the
    ///     move, ALREADY FLIPPED BACK to the MOVER's perspective (EngineLine
    ///     computes `afterEvalCp = -after.signedCp`). So "#2" means the player who
    ///     just moved has a forced mate in 2, and "#-2" means the move allowed the
    ///     opponent a forced mate in 2. Bare "#"/"#-" (no distance, as
    ///     `evalStrFromSignedCp` emits) are accepted too.
    ///
    /// Priority when a move matches more than one classification (documented
    /// choice, not incidental): **mate delivered > forced mate for the mover >
    /// forced mate allowed > material lost (the move hangs the moved piece) >
    /// material won by a capture > mistake/blunder naming the better move >
    /// best/good affirmation > generic fallback**. Mate outranks everything because
    /// it ends (or forcibly ends) the game; a hung piece outranks a capture's
    /// spoils because the loss is what the player must see; and both concrete
    /// material facts outrank the abstract classification label. A capture is only
    /// praised when the classification doesn't contradict it (a "blunder" that
    /// grabs a pawn while dropping the queen must not be congratulated).
    ///
    /// Never crashes on malformed/unparseable input — falls back to the generic
    /// template.
    public static func comment(
        fenBefore: String,
        fenAfter: String,
        moveUCI: String,
        moveSAN: String,
        classification: String,
        betterMoveSAN: String?,
        evalAfter: String?
    ) -> String {
        let cls = classification.lowercased()
        let better = betterMoveSAN.flatMap { $0.isEmpty ? nil : $0 }

        guard let move = BoardAttacks.parseUCI(moveUCI),
              let before = Position(fen: fenBefore) else {
            return genericTemplate
        }

        // Best-effort after-position: trust the caller's FEN, else re-derive it.
        let afterFEN: String? = Position(fen: fenAfter) != nil
            ? fenAfter
            : ChessLogic.fen(afterMove: moveUCI, fromFEN: fenBefore)

        // 1. Mate delivered on the board — nothing else matters.
        if let afterFEN, ChessLogic.status(forFEN: afterFEN) == .checkmate {
            return "Checkmate — game over."
        }

        // 2/3. Forced mate now on the board, for or against the mover.
        if let evalAfter, let mate = moverMate(fromEval: evalAfter) {
            if mate.forMover {
                switch mate.distance {
                case 1: return "Checkmate is one move away — go find it."
                case let n? where n > 1: return "You now have a forced mate in \(n) — finish it."
                default: return "Checkmate is now forced — close it out."
                }
            } else {
                if let better { return "This lets your opponent force checkmate — \(better) held on." }
                return "This lets your opponent force checkmate."
            }
        }

        // 4. The move leaves the moved piece hanging (en prise) — the concrete loss.
        if let afterFEN, let after = Position(fen: afterFEN),
           let piece = after.piece(at: move.to), isHanging(after, square: move.to) {
            let name = pieceNames[piece.kind] ?? "piece"
            if let better { return "That leaves your \(name) hanging — \(better) was safer." }
            return "That leaves your \(name) hanging."
        }

        // 5. A capture that wins material (only when the verdict doesn't contradict it).
        if cls != "mistake" && cls != "blunder",
           let capturedName = capturedPieceName(board: before, fenBefore: fenBefore, move: move) {
            return "That wins a \(capturedName) — nicely spotted."
        }

        // 6. Mistake/blunder/inaccuracy, naming the better move when we know it.
        switch cls {
        case "blunder":
            if let better { return "A blunder — \(better) kept the pressure." }
            return "A blunder — that gives away too much."
        case "mistake":
            if let better { return "A mistake — \(better) was stronger." }
            return "A mistake — there was a stronger option here."
        case "inaccuracy":
            if let better { return "A little imprecise — \(better) was more accurate." }
            return "A little imprecise — a sharper move was available."
        case "best":
            return "The engine's top choice — well played."
        case "good":
            return "A good, solid move."
        default:
            return genericTemplate
        }
    }

    // MARK: - Private classification

    /// Parses a mate distance out of an `evalAfter` string that is expressed from
    /// the MOVER's perspective ("#2", "#-2", or the distance-less "#"/"#-" that
    /// `EngineLine.evalStrFromSignedCp` emits). Returns `nil` when the string
    /// isn't a mate score at all.
    private static func moverMate(fromEval eval: String) -> (forMover: Bool, distance: Int?)? {
        guard eval.hasPrefix("#") else { return nil }
        let body = eval.dropFirst()                       // "2", "-2", or ""
        if body.isEmpty { return (forMover: true, distance: nil) }
        if body == "-" { return (forMover: false, distance: nil) }
        guard let n = Int(body) else { return nil }       // garbage after '#'
        return n > 0 ? (true, n) : (false, -n)
    }

    /// The name of the piece the move captures, including en passant, or `nil` if
    /// the move isn't a capture. Same shape as `HintRationaleTemplates`' helper.
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

    /// Static SEE-lite: is the piece on `square` left en prise (undefended, or won
    /// by a cheaper attacker)? Same definition as `Motifs`/`HintRationaleTemplates`,
    /// applied here to the played move's destination in the AFTER position — the
    /// backward-looking check the forward-looking hint templates can't do.
    private static func isHanging(_ position: Position, square: Square) -> Bool {
        guard let piece = position.piece(at: square) else { return false }
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
