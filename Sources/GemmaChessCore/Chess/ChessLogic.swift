//  ChessLogic.swift
//  A thin facade over `chesskit-swift` so the rest of the core depends on us,
//  not the library directly. This insulates callers from the dual-ChessKit split
//  and gives us one place for FEN/PGN/SAN/UCI parsing, EPD computation, legal-move
//  generation, and PV → SAN replay.
//
//  Ports the chess-logic helpers the source project got from python-chess
//  (FEN/EPD round-trips, `pv_to_san`, board replay) onto ChessKit primitives.

import Foundation
import ChessKit

/// Pure, deterministic chess helpers built on top of `chesskit-swift`.
///
/// Everything here is engine-free and side-effect-free: each call parses its
/// inputs, does the work, and returns a value (or `nil` on bad input), so it is
/// trivially testable and safe to call from any context.
public enum ChessLogic {

    // MARK: FEN

    /// Whether `fen` is a parseable chess position.
    public static func isValidFEN(_ fen: String) -> Bool {
        Position(fen: fen) != nil
    }

    /// Parse and re-serialize `fen`, normalizing it through ChessKit's parser.
    /// Returns `nil` if the FEN is invalid.
    public static func normalizedFEN(_ fen: String) -> String? {
        Position(fen: fen)?.fen
    }

    /// The EPD position key for a FEN: the first four space-separated fields
    /// (piece placement, side to move, castling rights, en passant target),
    /// dropping the halfmove clock and fullmove number.
    ///
    /// Two positions that differ only in move counters collapse to the same key,
    /// which is exactly what opening classification keys on. Returns `nil` if the
    /// FEN has fewer than four fields.
    public static func epd(fromFEN fen: String) -> String? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return nil }
        return fields[0..<4].joined(separator: " ")
    }

    // MARK: Position state

    /// The status of the side to move in a position.
    public enum Status: String, Equatable, Sendable {
        /// A normal position with legal moves and no check.
        case normal
        /// The side to move is in check but has legal moves.
        case check
        /// The side to move is checkmated (in check, no legal moves).
        case checkmate
        /// The side to move is stalemated (not in check, no legal moves).
        case stalemate
    }

    /// The side to move in `fen`, or `nil` if the FEN is invalid.
    public static func sideToMove(forFEN fen: String) -> Piece.Color? {
        Position(fen: fen)?.sideToMove
    }

    /// Whether the side to move in `fen` is in check.
    public static func isCheck(forFEN fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        return sideToMoveInCheck(position)
    }

    /// The status (normal / check / checkmate / stalemate) of the side to move in
    /// `fen`, or `nil` if the FEN is invalid.
    ///
    /// Terminal status is derived from check plus legal-move availability, which is
    /// robust for any raw FEN (`ChessKit`'s freshly-initialized `Board.state`
    /// reports check for the opponent of the side to move, not the side itself).
    public static func status(forFEN fen: String) -> Status? {
        guard let position = Position(fen: fen) else { return nil }
        let inCheck = sideToMoveInCheck(position)
        let hasMoves = !legalDestinations(forFEN: fen).isEmpty
        if inCheck { return hasMoves ? .check : .checkmate }
        return hasMoves ? .normal : .stalemate
    }

    /// Legal-move destinations for every piece of the side to move, keyed by the
    /// piece's square. Empty squares and the idle side's pieces are omitted.
    /// Returns an empty dictionary if the FEN is invalid.
    public static func legalDestinations(forFEN fen: String) -> [Square: [Square]] {
        guard let position = Position(fen: fen) else { return [:] }
        let board = Board(position: position)
        var result: [Square: [Square]] = [:]
        for piece in position.pieces where piece.color == position.sideToMove {
            let dests = board.legalMoves(forPieceAt: piece.square)
            if !dests.isEmpty {
                result[piece.square] = dests
            }
        }
        return result
    }

    // MARK: SAN <-> UCI

    /// Convert a SAN move (e.g. `"Nf3"`) to UCI/LAN (e.g. `"g1f3"`) in the context
    /// of `fen`. Returns `nil` if the FEN or move is invalid.
    public static func uci(fromSAN san: String, inFEN fen: String) -> String? {
        guard let position = Position(fen: fen),
              let move = Move(san: san, position: position) else { return nil }
        return move.lan
    }

    /// Convert a UCI/LAN move (e.g. `"g1f3"`, `"e7e8q"`) to SAN (e.g. `"Nf3"`,
    /// `"e8=Q"`) in the context of `fen`. The returned SAN includes check/mate
    /// markers. Returns `nil` if the FEN or move is invalid.
    public static func san(fromUCI uci: String, inFEN fen: String) -> String? {
        guard let position = Position(fen: fen) else { return nil }
        var board = Board(position: position)
        return apply(uci: uci, on: &board)
    }

    // MARK: Move application

    /// Apply a single move — given as SAN or UCI/LAN — to `fen` and return the
    /// resulting FEN. Returns `nil` if the FEN is invalid or the move is illegal.
    public static func fen(afterMove move: String, fromFEN fen: String) -> String? {
        guard let position = Position(fen: fen) else { return nil }
        var board = Board(position: position)

        // Resolve the move as SAN first, then fall back to UCI/LAN.
        let resolved: Move?
        if let m = Move(san: move, position: position) {
            resolved = m
        } else if let m = EngineLANParser.parse(move: move, for: position.sideToMove, in: position) {
            resolved = m
        } else {
            resolved = nil
        }

        guard let parsed = resolved,
              let made = board.move(pieceAt: parsed.start, to: parsed.end) else { return nil }
        if let promoted = parsed.promotedPiece {
            board.completePromotion(of: made, to: promoted.kind)
        }
        return board.position.fen
    }

    /// Replay a UCI/LAN principal variation onto the position in `fen`, collecting
    /// the SAN string for each move (with check/mate markers).
    ///
    /// Mirrors the source `pv_to_san`: moves are applied on a board in sequence and
    /// the SAN is captured as we go. Stops early at the first illegal move. At most
    /// `maxMoves` moves are converted.
    public static func pvToSAN(_ uciMoves: [String], fromFEN fen: String, maxMoves: Int = 12) -> [String] {
        guard maxMoves > 0, let position = Position(fen: fen) else { return [] }
        var board = Board(position: position)
        var sans: [String] = []
        for uci in uciMoves.prefix(maxMoves) {
            guard let san = apply(uci: uci, on: &board) else { break }
            sans.append(san)
        }
        return sans
    }

    // MARK: PGN replay

    /// The FEN of the final mainline position of a PGN, or `nil` if the PGN is
    /// unparseable. Used by opening classification to key a line by its endpoint.
    public static func finalFEN(forPGN pgn: String) -> String? {
        guard let game = try? Game(pgn: pgn) else { return nil }
        if let last = lastMainlineIndex(of: game), let position = game.positions[last] {
            return position.fen
        }
        return game.startingPosition?.fen
    }

    /// The FEN after every mainline move of a PGN, in play order (the starting
    /// position is not included). Returns `nil` if the PGN is unparseable, or an
    /// empty array for a moveless game.
    public static func fens(forPGN pgn: String) -> [String]? {
        guard let game = try? Game(pgn: pgn) else { return nil }
        guard let last = lastMainlineIndex(of: game) else { return [] }
        return game.moves.history(for: last).compactMap { game.positions[$0]?.fen }
    }

    // MARK: Private

    /// Apply one UCI/LAN move to `board`, returning its SAN (with check markers),
    /// or `nil` if the move is illegal in the current position.
    private static func apply(uci: String, on board: inout Board) -> String? {
        let position = board.position
        guard let parsed = EngineLANParser.parse(move: uci, for: position.sideToMove, in: position),
              let made = board.move(pieceAt: parsed.start, to: parsed.end) else { return nil }
        if let promoted = parsed.promotedPiece {
            return board.completePromotion(of: made, to: promoted.kind).san
        }
        return made.san
    }

    /// Whether the side to move in `position` is in check.
    ///
    /// Built by flipping the side to move and reading `Board.state`: with the
    /// opponent "to move", ChessKit's state computation reports check on the
    /// original side's king, which is the value we want.
    private static func sideToMoveInCheck(_ position: Position) -> Bool {
        guard let flipped = flippedSideToMove(of: position) else { return false }
        switch Board(position: flipped).state {
        case .check, .checkmate: return true
        default: return false
        }
    }

    /// A copy of `position` with the side to move toggled and the en passant target
    /// cleared, reconstructed via FEN. Returns `nil` only on an unexpected FEN
    /// round-trip failure.
    private static func flippedSideToMove(of position: Position) -> Position? {
        var fields = position.fen.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4 else { return nil }
        fields[1] = fields[1] == "w" ? "b" : "w"
        fields[3] = "-"  // en passant is irrelevant to check detection
        return Position(fen: fields.joined(separator: " "))
    }

    /// The deepest index of a game's main variation, or `nil` if there are no
    /// moves. Computed from the public index set since the library's
    /// `lastMainVariationIndex` is not exposed across modules.
    private static func lastMainlineIndex(of game: Game) -> MoveTree.Index? {
        game.moves.indices
            .filter { $0.variation == MoveTree.Index.mainVariation }
            .max()
    }
}
