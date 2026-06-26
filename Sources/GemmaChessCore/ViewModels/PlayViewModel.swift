//  PlayViewModel.swift
//  Play mode: start a new game, pick a side, move pieces by tapping, and get live
//  coaching after each of your moves. The opponent is Stockfish at an adjustable
//  Skill Level; coaching is the same engine-grounded, on-device coach used in review.

import SwiftUI
import ChessKit

/// The structured engine verdict on the user's latest move, powering the coach card.
public struct MoveVerdict: Equatable, Sendable {
    public var moveSAN: String
    public var classification: String      // best/good/inaccuracy/mistake/blunder…
    public var isBest: Bool
    public var betterMoveSAN: String?
    public init(moveSAN: String, classification: String, isBest: Bool, betterMoveSAN: String?) {
        self.moveSAN = moveSAN; self.classification = classification
        self.isBest = isBest; self.betterMoveSAN = betterMoveSAN
    }

    /// Colour for a classification: best/good → accent, inaccuracy → gold,
    /// mistake → orange, blunder → red.
    public static func color(for classification: String) -> Color {
        switch classification.lowercased() {
        case "best", "good": return GemmaTheme.accent
        case "inaccuracy": return GemmaTheme.gold
        case "mistake": return .orange
        case "blunder": return .red
        default: return GemmaTheme.accent
        }
    }
}

@MainActor
@Observable
public final class PlayViewModel {

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    // MARK: State
    public var fen: String = PlayViewModel.startFEN
    public var playerIsWhite: Bool = true
    public var moves: [String] = []                 // UCI list, in order
    public var lastMove: (from: Square, to: Square)?
    public var selected: Square?
    public var status: String = "Your move"
    public var coachNotes: [(role: String, text: String)] = []
    public var engineThinking: Bool = false
    public var isCoaching: Bool = false
    public var gameOver: Bool = false
    public var resultText: String?
    /// Opponent strength: Stockfish "Skill Level" 0–20.
    public var skill: Int = 6
    public var coachAvailability: CoachAvailability
    /// Live engine read-out of the current position (White's perspective).
    public var winWhite: Double = 50
    public var evalText: String = "0.0"

    // MARK: History + viewing cursor (U6)
    /// Position after each ply, with the start FEN at index 0 (so `fenHistory[k]`
    /// is the position *before* the (k+1)-th move). Accumulated at move time.
    public var fenHistory: [String] = [PlayViewModel.startFEN]
    /// SAN for each ply, in order (parallel to `moves`). Accumulated at move time.
    public var sanMoves: [String] = []
    /// Node being viewed (index into `fenHistory`), or nil when showing the live game.
    public var viewingPly: Int?

    // MARK: Best-move graphics (U5)
    /// Cached best move (UCI) per FEN, so re-renders don't re-analyse.
    public var bestMoveCache: [String: String] = [:]
    /// Number of real engine analyses performed for best-move hints (test hook).
    public private(set) var bestMoveAnalysisCount = 0
    private var bestMoveInFlight: Set<String> = []

    // MARK: Coach card (U7)
    /// Structured engine verdict on the user's latest move.
    public var lastVerdict: MoveVerdict?
    /// The coach's short "what to focus on" note for the latest move.
    public var lastCoachNote: String?

    private var dests: [Square: [Square]] = [:]
    private let coach: CoachOrchestrator

    public init(coach: CoachOrchestrator = CoachOrchestrator()) {
        self.coach = coach
        self.coachAvailability = coach.availability
    }

    // MARK: Derived
    public var orientation: BoardOrientation { playerIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }
    public var coachEnabled: Bool {
        if case .unavailable = coachAvailability { return false }
        return true
    }

    /// True when the user is browsing a past position rather than the live game.
    public var isViewingHistory: Bool { viewingPly != nil }

    /// The FEN currently shown on the board: the viewed node when browsing, else live.
    public var displayFEN: String {
        if let p = viewingPly, fenHistory.indices.contains(p) { return fenHistory[p] }
        return fen
    }

    /// Captured material for the shown position (live or viewing).
    public var capturedMaterial: CapturedMaterial { CapturedMaterial.from(fen: displayFEN) }

    /// The move highlighted on the shown board: the viewed node's outgoing move when
    /// browsing, else the live last move.
    public var displayLastMove: (from: Square, to: Square)? {
        if let p = viewingPly, moves.indices.contains(p) { return squares(fromUCI: moves[p]) }
        return lastMove
    }

    public var userToMove: Bool {
        (ChessLogic.sideToMove(forFEN: fen) == .white) == playerIsWhite
    }

    // MARK: Viewing cursor (U6)

    /// Browse the position before move `ply` (0-based index into `moves`).
    public func viewTo(ply: Int) {
        guard fenHistory.indices.contains(ply) else { return }
        viewingPly = ply
        selected = nil
    }

    /// Return to the live game.
    public func returnToLive() { viewingPly = nil }

    // MARK: Best-move graphics (U5)

    /// The cached best move (UCI) for a FEN, or nil if not yet analysed.
    public func bestMove(forFEN fen: String) -> String? { bestMoveCache[fen] }

    /// Ensure the best move for `fen` is analysed and cached. Cheap & idempotent:
    /// repeated calls for the same FEN don't trigger a second analysis.
    public func requestBestMove(forFEN fen: String) {
        guard bestMoveCache[fen] == nil, !bestMoveInFlight.contains(fen) else { return }
        guard ChessLogic.status(forFEN: fen).map({ $0 == .normal || $0 == .check }) ?? false else { return }
        bestMoveInFlight.insert(fen)
        bestMoveAnalysisCount += 1
        Task {
            defer { bestMoveInFlight.remove(fen) }
            guard let report = try? await EngineLine.evaluate(fen: fen, depth: 12, multipv: 1),
                  let uci = report.lineUCI.first else { return }
            bestMoveCache[fen] = uci
        }
    }

    // MARK: Game lifecycle

    public func newGame(asWhite: Bool) {
        playerIsWhite = asWhite
        fen = Self.startFEN
        moves = []
        lastMove = nil
        selected = nil
        gameOver = false
        resultText = nil
        coachNotes = []
        winWhite = 50
        evalText = "0.0"
        fenHistory = [Self.startFEN]
        sanMoves = []
        viewingPly = nil
        bestMoveCache = [:]
        bestMoveInFlight = []
        bestMoveAnalysisCount = 0
        lastVerdict = nil
        lastCoachNote = nil
        coachAvailability = coach.availability
        refreshDests()
        refreshEval()
        if asWhite {
            status = "Your move"
        } else {
            status = "Engine is thinking…"
            Task { await engineReply() }
        }
    }

    public func resign() {
        guard !gameOver else { return }
        gameOver = true
        resultText = "You resigned."
        status = resultText!
    }

    // MARK: Tap-to-move

    public func tap(_ square: Square) {
        guard !isViewingHistory, !gameOver, userToMove, !engineThinking else { return }
        if let sel = selected, let d = dests[sel], d.contains(square) {
            makeUserMove(from: sel, to: square)
            return
        }
        selected = (dests[square] != nil) ? square : nil
    }

    private func makeUserMove(from: Square, to: Square) {
        returnToLive()   // a move only happens on the live board
        let fromFEN = fen
        let uci = uci(from: from, to: to, in: fromFEN)
        guard let afterFEN = ChessLogic.fen(afterMove: uci, fromFEN: fromFEN) else { return }

        fen = afterFEN
        moves.append(uci)
        sanMoves.append(ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci)
        fenHistory.append(afterFEN)
        lastMove = (from, to)
        selected = nil
        refreshDests()
        refreshEval()

        if checkGameOver(youMoved: true) { return }
        status = "Engine is thinking…"
        Task {
            await engineReply()
            await coachOnMove(fromFEN: fromFEN, uci: uci, afterFEN: afterFEN)
        }
    }

    private func engineReply() async {
        guard !gameOver else { return }
        engineThinking = true
        defer { engineThinking = false }
        do {
            if let reply = try await EnginePool.shared.playMove(fen: fen, depth: 12, skill: skill),
               let next = ChessLogic.fen(afterMove: reply, fromFEN: fen) {
                let fromFEN = fen
                fen = next
                moves.append(reply)
                sanMoves.append(ChessLogic.san(fromUCI: reply, inFEN: fromFEN) ?? reply)
                fenHistory.append(next)
                lastMove = squares(fromUCI: reply)
                refreshDests()
                refreshEval()
                _ = checkGameOver(youMoved: false)
            }
        } catch {
            // engine hiccup — leave it the user's move
        }
        if !gameOver { status = "Your move" }
    }

    /// Immediate engine verdict on the move you just played, then a short coach note.
    private func coachOnMove(fromFEN: String, uci: String, afterFEN: String) async {
        isCoaching = true
        defer { isCoaching = false }
        let san = ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci
        lastCoachNote = nil

        if let report = try? await EngineLine.evaluate(fen: fromFEN, move: uci, depth: 14, multipv: 1),
           let mv = report.move {
            lastVerdict = MoveVerdict(
                moveSAN: san,
                classification: mv.classification,
                isBest: mv.isEngineBest,
                betterMoveSAN: mv.isEngineBest ? nil : mv.betterMoveSAN
            )
        }

        guard coachEnabled else { return }
        if let reply = try? await coach.answer(
            question: "I just played \(san). Briefly: how was it, and what should I focus on now?",
            fen: afterFEN, lastMove: uci, moveFen: fromFEN, sessionID: nil
        ) {
            lastCoachNote = reply.answer
        }
    }

    // MARK: Helpers

    private func refreshDests() { dests = ChessLogic.legalDestinations(forFEN: fen) }

    /// Analyse the current position (cheaply) to drive the eval bar + win% readout.
    func refreshEval() {
        let position = fen
        Task {
            guard let result = try? await EnginePool.shared.analyse(fen: position, depth: 12, multipv: 1) else { return }
            guard position == fen else { return }   // board moved on; drop stale result
            let best = result.best
            let stmWhite = ChessLogic.sideToMove(forFEN: position) == .white
            winWhite = stmWhite ? best.winPercent : 100 - best.winPercent
            let whiteCp = Int((stmWhite ? best.signedCp : -best.signedCp).rounded())
            evalText = EngineLine.evalStrFromSignedCp(whiteCp)
        }
    }

    @discardableResult
    private func checkGameOver(youMoved: Bool) -> Bool {
        switch ChessLogic.status(forFEN: fen) {
        case .checkmate:
            gameOver = true
            let stmWhite = ChessLogic.sideToMove(forFEN: fen) == .white
            let matedIsUser = (stmWhite == playerIsWhite)   // side to move is the mated one
            resultText = matedIsUser ? "Checkmate — you lose." : "Checkmate — you win! 🎉"
            status = resultText!
            return true
        case .stalemate:
            gameOver = true
            resultText = "Stalemate — it's a draw."
            status = resultText!
            return true
        default:
            return false
        }
    }

    private func notation(_ sq: Square) -> String {
        let file = Square.File.allCases[sq.file.number - 1].rawValue
        return "\(file)\(sq.rank.value)"
    }

    /// Build a UCI move, auto-queening a pawn that reaches the last rank.
    private func uci(from: Square, to: Square, in fen: String) -> String {
        let placement = BoardGeometry.placement(fromFEN: fen)
        let idx = (from.rank.value - 1) * 8 + (from.file.number - 1)
        let isPawn = placement[idx].map { $0 == "p" || $0 == "P" } ?? false
        let promo = (isPawn && (to.rank.value == 8 || to.rank.value == 1)) ? "q" : ""
        return notation(from) + notation(to) + promo
    }

    private func squares(fromUCI uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4,
              let from = BoardGeometry.square(String(uci.prefix(2))),
              let to = BoardGeometry.square(String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }
}
