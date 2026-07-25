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

    /// The checked king's square and the opposing piece(s) directly attacking it,
    /// when the side to move in `fen` is in check (check OR checkmate) -- nil
    /// otherwise. This is what lets the board actually show WHY it's check/mate,
    /// not just announce it.
    public static func checkAttackers(forFEN fen: String) -> (king: Square, attackers: [Square])? {
        guard let position = Position(fen: fen), sideToMoveInCheck(position) else { return nil }
        let kingColor = position.sideToMove
        guard let king = position.pieces.first(where: { $0.color == kingColor && $0.kind == .king })
        else { return nil }
        let attackerColor: Piece.Color = kingColor == .white ? .black : .white
        let attackers = BoardAttacks.attackers(of: attackerColor, on: king.square, in: position)
        guard !attackers.isEmpty else { return nil }
        return (king.square, attackers)
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

    // MARK: Why is it over?

    /// Why a position is terminal: which king is trapped (or which side has run out
    /// of moves), and, square by square, what stops the king from stepping away.
    ///
    /// Deliberately keeps square identities rather than booleans so a UI layer can
    /// both tint the board and build a spoken summary from the same value.
    public struct TerminalExplanation: Equatable, Sendable {

        /// Which kind of ending this is.
        public enum Reason: String, Equatable, Sendable {
            case checkmate
            case stalemate
        }

        /// Why one of the king's steps is not an escape.
        public enum Availability: Equatable, Sendable {
            /// The square holds one of the mated side's own pieces.
            case blockedByOwnPiece(Piece.Kind)
            /// The square is empty (or holds a capturable enemy piece) but stepping
            /// there stays in check. `squares` names the enemy pieces responsible,
            /// including a checking slider that x-rays through the king.
            case covered(by: [Square])
        }

        /// One step the king could otherwise take, and what stops it.
        public struct FlightSquare: Equatable, Sendable {
            public let square: Square
            public let availability: Availability

            public init(square: Square, availability: Availability) {
                self.square = square
                self.availability = availability
            }
        }

        /// Checkmate or stalemate.
        public let reason: Reason
        /// The side that is mated or stalemated (the side to move).
        public let side: Piece.Color
        /// That side's king square. For stalemate this is where the king stands, not
        /// a claim that it is attacked.
        public let kingSquare: Square
        /// The enemy pieces giving check. Empty for stalemate.
        public let checkers: [Square]
        /// Every pseudo-legal king step, with the reason it is unavailable. Empty for
        /// stalemate, where the ending is not about king-trap geometry.
        public let flightSquares: [FlightSquare]
        /// For stalemate: every piece of `side`, none of which has a legal move.
        /// Empty for checkmate.
        public let stuckPieces: [Square]

        public init(
            reason: Reason,
            side: Piece.Color,
            kingSquare: Square,
            checkers: [Square],
            flightSquares: [FlightSquare],
            stuckPieces: [Square]
        ) {
            self.reason = reason
            self.side = side
            self.kingSquare = kingSquare
            self.checkers = checkers
            self.flightSquares = flightSquares
            self.stuckPieces = stuckPieces
        }
    }

    /// Explain *why* `fen` is checkmate or stalemate, or `nil` when the position is
    /// not terminal (or the FEN is unparseable).
    ///
    /// Availability of a king step is decided by actually playing the move and asking
    /// whether the king is still attacked afterwards. That is authoritative and, in
    /// particular, correct for x-rays: `BoardAttacks.attackers(of:on:)` runs against
    /// the current position, where the king still blocks a checking slider's ray, so
    /// the square directly behind the king reads as unattacked even though it is not
    /// an escape. The attacker query is therefore used only to *name* the pieces
    /// covering a square that is already known to be unavailable.
    public static func terminalExplanation(forFEN fen: String) -> TerminalExplanation? {
        guard let position = Position(fen: fen), let outcome = status(forFEN: fen) else { return nil }
        let side = position.sideToMove
        guard let king = position.pieces.first(where: { $0.color == side && $0.kind == .king })
        else { return nil }
        let enemy: Piece.Color = side == .white ? .black : .white

        switch outcome {
        case .normal, .check:
            return nil

        case .stalemate:
            // "No piece has a legal move" is the whole story; report it as such and
            // do not claim the king is checked.
            let stuck = position.pieces
                .filter { $0.color == side }
                .map(\.square)
                .sorted { $0.rawValue < $1.rawValue }
            return TerminalExplanation(
                reason: .stalemate, side: side, kingSquare: king.square,
                checkers: [], flightSquares: [], stuckPieces: stuck
            )

        case .checkmate:
            let checkers = BoardAttacks.attackers(of: enemy, on: king.square, in: position)
            var flights: [TerminalExplanation.FlightSquare] = []
            let steps = BoardAttacks.attackSquares(of: king, in: position)
                .sorted { $0.rawValue < $1.rawValue }

            for step in steps {
                if let occupant = position.piece(at: step), occupant.color == side {
                    flights.append(.init(square: step, availability: .blockedByOwnPiece(occupant.kind)))
                    continue
                }
                // Authoritative: play the move and see whether the king is safe there.
                if kingEscapes(from: king.square, to: step, side: side, fromFEN: fen) { continue }
                var coverers = BoardAttacks.attackers(of: enemy, on: step, in: position)
                if coverers.isEmpty {
                    coverers = xRayCoverers(of: step, kingSquare: king.square,
                                            checkers: checkers, in: position)
                }
                flights.append(.init(square: step, availability: .covered(by: coverers)))
            }

            return TerminalExplanation(
                reason: .checkmate, side: side, kingSquare: king.square,
                checkers: checkers, flightSquares: flights, stuckPieces: []
            )
        }
    }

    /// Whether the king can legally step from `origin` to `target`: the move is made
    /// on a real board and the resulting position is queried with the king already
    /// out of the way, so x-rayed squares resolve correctly.
    private static func kingEscapes(
        from origin: Square, to target: Square, side: Piece.Color, fromFEN fenString: String
    ) -> Bool {
        guard let after = fen(afterMove: origin.notation + target.notation, fromFEN: fenString),
              let position = Position(fen: after),
              let king = position.pieces.first(where: { $0.color == side && $0.kind == .king })
        else { return false }
        let enemy: Piece.Color = side == .white ? .black : .white
        return BoardAttacks.attackers(of: enemy, on: king.square, in: position).isEmpty
    }

    /// Checking sliders whose ray runs through the king and onto `target` — the
    /// squares `attackers(of:on:)` cannot see, because the king blocks the ray.
    private static func xRayCoverers(
        of target: Square, kingSquare: Square, checkers: [Square], in position: Position
    ) -> [Square] {
        func step(_ delta: Int) -> Int { delta == 0 ? 0 : (delta > 0 ? 1 : -1) }
        let kf = BoardAttacks.file(kingSquare), kr = BoardAttacks.rank(kingSquare)
        return checkers.filter { checker in
            guard let piece = position.piece(at: checker),
                  piece.kind == .rook || piece.kind == .bishop || piece.kind == .queen
            else { return false }
            let df = step(kf - BoardAttacks.file(checker))
            let dr = step(kr - BoardAttacks.rank(checker))
            return BoardAttacks.square(file: kf + df, rank: kr + dr) == target
        }
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
