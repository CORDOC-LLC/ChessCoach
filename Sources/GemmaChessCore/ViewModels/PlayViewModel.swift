//  PlayViewModel.swift
//  Play mode: start a new game, pick a side, move pieces by tapping, and get live
//  coaching after each of your moves. The opponent is Stockfish at an adjustable
//  Skill Level; coaching is the same engine-grounded, on-device coach used in review.

import SwiftUI
import ChessKit

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

    private var userToMove: Bool {
        (ChessLogic.sideToMove(forFEN: fen) == .white) == playerIsWhite
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
        guard !gameOver, userToMove, !engineThinking else { return }
        if let sel = selected, let d = dests[sel], d.contains(square) {
            makeUserMove(from: sel, to: square)
            return
        }
        selected = (dests[square] != nil) ? square : nil
    }

    private func makeUserMove(from: Square, to: Square) {
        let fromFEN = fen
        let uci = uci(from: from, to: to, in: fromFEN)
        guard let afterFEN = ChessLogic.fen(afterMove: uci, fromFEN: fromFEN) else { return }

        fen = afterFEN
        moves.append(uci)
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
                fen = next
                moves.append(reply)
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

        if let report = try? await EngineLine.evaluate(fen: fromFEN, move: uci, depth: 14, multipv: 1),
           let mv = report.move {
            let tail = mv.isEngineBest
                ? " — the engine's top move."
                : ", best was \(mv.betterMoveSAN ?? "?")."
            coachNotes.append((role: "engine", text: "\(san): \(mv.classification)\(tail)"))
        }

        guard coachEnabled else { return }
        if let reply = try? await coach.answer(
            question: "I just played \(san). Briefly: how was it, and what should I focus on now?",
            fen: afterFEN, lastMove: uci, moveFen: fromFEN, sessionID: nil
        ) {
            coachNotes.append((role: "coach", text: reply.answer))
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
