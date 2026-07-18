//  OpeningTrainerViewModel.swift
//  Opening Trainer: search the local ECO book for a line, then drill it one
//  move at a time -- the trainer auto-plays the opponent's moves and prompts
//  for the user's, tracking familiarity locally via OpeningTrainerStore.
//  Entirely free -- no coach, no network; move checking is a plain SAN/UCI
//  compare against the line's own moves, same as PuzzleViewModel's approach.

import SwiftUI
import ChessKit

/// Transient feedback on the drill's last attempt.
public enum OpeningTrainerFeedback: Equatable, Sendable {
    case correct
    case incorrect
    case lineComplete
}

@MainActor
@Observable
public final class OpeningTrainerViewModel {

    private static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    // MARK: Search
    public var searchQuery: String = "" {
        didSet { results = Openings.search(searchQuery) }
    }
    public private(set) var results: [Openings.OpeningLine] = Openings.search("")

    // MARK: Session
    public private(set) var activeLine: Openings.OpeningLine?
    public var userIsWhite = true
    public var fen: String = OpeningTrainerViewModel.startingFEN
    public var lastMove: (from: Square, to: Square)?
    public var selected: Square?
    public var status: String = ""
    public var feedback: OpeningTrainerFeedback?
    /// The line's own next move, surfaced after an incorrect attempt.
    public var correctContinuationSAN: String?
    public private(set) var familiarity: OpeningFamiliarity?

    private var dests: [Square: [Square]] = [:]
    private var moveCursor = 0
    private var sessionGen = 0
    /// Injectable so tests use scratch storage instead of `UserDefaults.standard`.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Derived

    public var orientation: BoardOrientation { userIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }
    public var isLineFinished: Bool {
        guard let line = activeLine else { return false }
        return moveCursor >= line.sanMoves.count
    }

    private var isUsersTurn: Bool {
        // Ply 0 (moveCursor even) is White to move.
        (moveCursor % 2 == 0) == userIsWhite
    }

    // MARK: Search

    public func search(_ query: String) {
        searchQuery = query
    }

    // MARK: Starting/ending a drill

    public func start(line: Openings.OpeningLine, userIsWhite: Bool = true) {
        sessionGen += 1
        activeLine = line
        self.userIsWhite = userIsWhite
        fen = Self.startingFEN
        moveCursor = 0
        selected = nil
        lastMove = nil
        feedback = nil
        correctContinuationSAN = nil
        familiarity = OpeningTrainerStore.familiarity(for: line.id, defaults: defaults)
        refreshDests()
        advanceAutoMoves()
    }

    public func endSession() {
        sessionGen += 1
        activeLine = nil
    }

    /// Lines whose review is due now, ranked ahead of the rest (used to
    /// suggest what to drill next rather than a bare alphabetical list).
    public func dueLines() -> [Openings.OpeningLine] {
        OpeningTrainerStore.linesDueForReview(from: results, defaults: defaults)
    }

    // MARK: Tap-to-move

    public func tap(_ square: Square) {
        guard activeLine != nil, !isLineFinished, feedback != .lineComplete else { return }
        if let sel = selected, let d = dests[sel], d.contains(square) {
            attemptMove(from: sel, to: square)
            return
        }
        selected = (dests[square] != nil) ? square : nil
    }

    // MARK: Move handling

    private func attemptMove(from: Square, to: Square) {
        guard let line = activeLine, moveCursor < line.sanMoves.count else { return }
        let fromFEN = fen
        let expectedSAN = line.sanMoves[moveCursor]
        let expectedUCI = ChessLogic.uci(fromSAN: expectedSAN, inFEN: fromFEN)
        let attemptedUCI = uci(from: from, to: to, in: fromFEN)
        selected = nil

        let isLineComplete = moveCursor == line.sanMoves.count - 1

        guard attemptedUCI == expectedUCI else {
            familiarity = OpeningTrainerStore.recordAttempt(
                correct: false, lineID: line.id, isLineComplete: isLineComplete, defaults: defaults)
            feedback = .incorrect
            correctContinuationSAN = expectedSAN
            status = "Not quite — the line continues \(expectedSAN)."
            return
        }

        guard applyMove(expectedSAN) else { return }
        familiarity = OpeningTrainerStore.recordAttempt(
            correct: true, lineID: line.id, isLineComplete: isLineComplete, defaults: defaults)
        feedback = .correct
        correctContinuationSAN = nil

        if isLineFinished {
            finishLine()
            return
        }
        status = "Correct!"
        let gen = sessionGen
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard gen == self.sessionGen else { return }
            self.advanceAutoMoves()
            if self.isLineFinished {
                self.finishLine()
            } else {
                self.feedback = nil
                self.status = "Your move."
            }
        }
    }

    private func finishLine() {
        feedback = .lineComplete
        status = (familiarity?.isLearned == true) ? "Line learned!" : "Line complete!"
    }

    /// Plays every consecutive move that isn't the user's, stopping once it's
    /// the user's turn or the line runs out.
    private func advanceAutoMoves() {
        guard let line = activeLine else { return }
        while moveCursor < line.sanMoves.count, !isUsersTurn {
            guard applyMove(line.sanMoves[moveCursor]) else { break }
        }
        if !isLineFinished {
            status = "Your move."
        }
    }

    @discardableResult
    private func applyMove(_ san: String) -> Bool {
        guard let uci = ChessLogic.uci(fromSAN: san, inFEN: fen),
              let next = ChessLogic.fen(afterMove: san, fromFEN: fen)
        else { return false }
        lastMove = squares(fromUCI: uci)
        fen = next
        moveCursor += 1
        refreshDests()
        return true
    }

    private func refreshDests() { dests = ChessLogic.legalDestinations(forFEN: fen) }

    private func notation(_ sq: Square) -> String {
        let file = Square.File.allCases[sq.file.number - 1].rawValue
        return "\(file)\(sq.rank.value)"
    }

    /// Build a UCI move, auto-queening a pawn that reaches the last rank
    /// (mirrors PuzzleViewModel -- the user never picks an underpromotion here).
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
