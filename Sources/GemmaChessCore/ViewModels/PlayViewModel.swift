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

/// An on-demand hint: the engine's best move plus a good alternative, with an
/// optional one-line coach rationale. Distinct from the always-on best-move toggle —
/// it is requested explicitly and dismissed by the user.
public struct HintInfo: Equatable, Sendable {
    public var bestUCI: String
    public var secondUCI: String?
    public var bestSAN: String
    public var secondSAN: String?
    public var rationale: String?
    public var isLoading: Bool
    public init(bestUCI: String, secondUCI: String?, bestSAN: String,
                secondSAN: String?, rationale: String?, isLoading: Bool) {
        self.bestUCI = bestUCI; self.secondUCI = secondUCI
        self.bestSAN = bestSAN; self.secondSAN = secondSAN
        self.rationale = rationale; self.isLoading = isLoading
    }

    /// One-line summary for the hint card header, e.g. "Best: Nf3 · Alt: e4".
    public var summaryLabel: String {
        if let alt = secondSAN { return "Best: \(bestSAN) · Alt: \(alt)" }
        return "Best: \(bestSAN)"
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

    // MARK: On-demand hint
    /// The current hint, or nil when none is shown. Set by `requestHint`, cleared by
    /// `clearHint`, a new move, or a new game.
    public var hint: HintInfo?

    // MARK: End-of-game summary + retry (the teach-back loop)
    /// The coach's written debrief of the finished game, streamed in at game over.
    public var gameSummary: String?
    /// True while the debrief is being generated.
    public var isSummarizing = false
    /// Every graded user move this game — the inputs to the end-of-game summary.
    private(set) var moveRecords: [CoachPromptBuilder.PlayMoveRecord] = []
    /// Snapshot taken before each user move so "try again" can rewind to it.
    private var retryBase: (fen: String, moveCount: Int)?
    /// Bumped by retry/new game so in-flight verdict/note/summary tasks abandon
    /// their writes instead of scribbling on the rewound game.
    private var moveGen = 0

    // MARK: Opening recognition
    /// The deepest named opening the game has reached so far (lichess chess-openings
    /// book), refined live after every ply. Never regresses: an out-of-book move
    /// keeps the last named line ("you left the London with …" still reads right).
    public var opening: Openings.Opening?

    private var dests: [Square: [Square]] = [:]
    private let coach: CoachOrchestrator

    public init(coach: CoachOrchestrator = CoachOrchestrator()) {
        self.coach = coach
        self.coachAvailability = coach.availability
    }

    // MARK: Derived
    public var orientation: BoardOrientation { playerIsWhite ? .white : .black }
    public var legalDots: [Square] { selected.flatMap { dests[$0] } ?? [] }
    /// Mirrors the "Coach" show/hide toggle in the ⋯ menu (`PlayDisplaySettings.
    /// showCoach`, wired in by the view). Folded into `coachEnabled` itself —
    /// not just hiding the card — so turning the coach off actually stops the
    /// per-move note, hint rationale, chat, and end-of-game debrief network
    /// calls, instead of just hiding their output.
    public var coachDisplayEnabled: Bool = true

    public var coachEnabled: Bool {
        if case .unavailable = coachAvailability { return false }
        return coachDisplayEnabled
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
            guard let report = try? await EngineLine.evaluate(fen: fen, depth: GCConfig.liveDepth, multipv: 1),
                  let uci = report.lineUCI.first else { return }
            bestMoveCache[fen] = uci
        }
    }

    // MARK: On-demand hint

    /// Analyse the live position at multipv 2 for the best move + a good alternative,
    /// then (if a coach is available) attach a short rationale. Only valid at the
    /// user's live turn — ignored while browsing history or after game over.
    public func requestHint() {
        guard !isViewingHistory, !gameOver, userToMove else { return }
        let position = fen
        hint = HintInfo(bestUCI: "", secondUCI: nil, bestSAN: "", secondSAN: nil,
                        rationale: nil, isLoading: true)
        Task {
            guard let report = try? await EngineLine.evaluate(fen: position, depth: GCConfig.liveDepth, multipv: 2) else {
                if position == fen { hint = nil }
                return
            }
            guard position == fen else { return }   // board moved on; drop stale result
            let lines = report.lines
            guard let bestUCI = lines.first?.lineUCI.first ?? report.lineUCI.first else {
                hint = nil; return
            }
            let bestSAN = lines.first?.lineSAN.first ?? report.bestSAN ?? bestUCI
            let secondUCI = lines.count > 1 ? lines[1].lineUCI.first : nil
            let secondSAN = lines.count > 1 ? lines[1].lineSAN.first : nil
            hint = HintInfo(
                bestUCI: bestUCI, secondUCI: secondUCI,
                bestSAN: bestSAN, secondSAN: secondSAN,
                rationale: nil, isLoading: coachEnabled
            )

            guard coachEnabled else { return }
            // Ground the rationale in the SAME analysis that drew the arrows (passed
            // as currentFacts so the orchestrator does no second engine run), and
            // stream it so the reason appears as it's written instead of after a wait.
            let facts = CoachPromptBuilder.engineFactsText(report.coachInfo)
            var question = "Why is \(bestSAN) the strongest move here? One or two short sentences on the idea behind it."
            if let alt = secondSAN {
                question += " Add one short sentence on when \(alt) is a fine alternative."
            }
            do {
                let stream = try await coach.answerStream(
                    question: question,
                    fen: position, playerSide: playerIsWhite ? .white : .black,
                    openingFacts: openingFacts, currentFacts: facts,
                    depth: GCConfig.liveDepth
                )
                for try await partial in stream {
                    guard position == fen, hint != nil else { return }
                    hint?.rationale = partial
                }
            } catch {
                // No rationale — the arrows and SANs still stand on their own.
            }
            if position == fen { hint?.isLoading = false }
        }
    }

    /// Dismiss the current hint.
    public func clearHint() { hint = nil }

    // MARK: Game lifecycle

    /// Starts a new game. `startFEN` defaults to the standard opening position;
    /// pass a recognized board-photo FEN to start from an arbitrary position
    /// instead (e.g. after `ManagedVisionClient.recognizeBoard`). `asWhite` is
    /// which side the USER plays, independent of whose move `startFEN` has —
    /// so scanning a photo where it's Black's move with the user playing
    /// White correctly hands the first move to the engine.
    public func newGame(asWhite: Bool, startFEN: String = PlayViewModel.startFEN) {
        playerIsWhite = asWhite
        fen = startFEN
        moves = []
        lastMove = nil
        selected = nil
        gameOver = false
        resultText = nil
        coachNotes = []
        winWhite = 50
        evalText = "0.0"
        fenHistory = [startFEN]
        sanMoves = []
        viewingPly = nil
        bestMoveCache = [:]
        bestMoveInFlight = []
        bestMoveAnalysisCount = 0
        lastVerdict = nil
        lastCoachNote = nil
        hint = nil
        opening = nil
        gameSummary = nil
        isSummarizing = false
        moveRecords = []
        retryBase = nil
        moveGen += 1
        chat = []
        isAsking = false
        coachAvailability = coach.availability
        refreshDests()
        refreshEval()
        let userToMoveNow = (ChessLogic.sideToMove(forFEN: startFEN) == .white) == asWhite
        if userToMoveNow {
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
        startGameSummary()
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
        hint = nil       // a fresh position invalidates any showing hint
        let fromFEN = fen
        let uci = uci(from: from, to: to, in: fromFEN)
        guard let afterFEN = ChessLogic.fen(afterMove: uci, fromFEN: fromFEN) else { return }

        // The rewind point for "try again": the position before this move.
        retryBase = (fen: fromFEN, moveCount: moves.count)
        let moveNumber = moves.count / 2 + 1
        fen = afterFEN
        moves.append(uci)
        sanMoves.append(ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci)
        fenHistory.append(afterFEN)
        lastMove = (from, to)
        selected = nil
        refreshDests()
        refreshEval()

        updateOpening(afterFEN: afterFEN)
        if checkGameOver(youMoved: true) { return }
        status = "Engine is thinking…"
        // Show the coach as busy from the instant you move (it used to look idle
        // until the engine had already replied).
        isCoaching = true
        lastVerdict = nil
        lastCoachNote = nil
        let gen = moveGen
        Task {
            // ONE analysis serves both the verdict chip and the coach's move facts
            // (this used to be analysed twice). The chip appears right away.
            let moveReport = try? await EngineLine.evaluate(
                fen: fromFEN, move: uci, depth: GCConfig.liveDepth, multipv: 2)
            guard gen == moveGen else { return }   // retried/new game while analysing
            if let mv = moveReport?.move {
                let san = ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci
                lastVerdict = MoveVerdict(
                    moveSAN: san, classification: mv.classification,
                    isBest: mv.isEngineBest, betterMoveSAN: mv.isEngineBest ? nil : mv.betterMoveSAN)
                moveRecords.append(CoachPromptBuilder.PlayMoveRecord(
                    moveNumber: moveNumber, san: san, classification: mv.classification,
                    winBefore: mv.winBefore, winAfter: mv.winAfter,
                    betterSan: mv.isEngineBest ? nil : mv.betterMoveSAN))
            }
            let replySAN = await engineReply()
            guard gen == moveGen else { return }
            await streamCoachNote(fromFEN: fromFEN, uci: uci, moveReport: moveReport,
                                  opponentReplySAN: replySAN, gen: gen)
            if gen == moveGen { isCoaching = false }
        }
    }

    // MARK: Try again (the blunder-retry teaching loop)

    /// True when the last graded move can be taken back and retried: it lost ground
    /// (inaccuracy or worse) and the engine isn't mid-reply. Works after game over
    /// too — undoing the losing blunder un-ends the game.
    public var canRetry: Bool {
        guard let v = lastVerdict, retryBase != nil, !engineThinking, !isViewingHistory else { return false }
        return ["inaccuracy", "mistake", "blunder"].contains(v.classification.lowercased())
    }

    /// Rewind to just before your last move so you can find the better one yourself —
    /// the strongest teaching loop there is. Removes your move (and the engine's
    /// reply, if made) from the game; any in-flight coach work is abandoned.
    public func retryLastMove() {
        guard canRetry, let base = retryBase else { return }
        moveGen += 1
        fen = base.fen
        moves = Array(moves.prefix(base.moveCount))
        sanMoves = Array(sanMoves.prefix(base.moveCount))
        fenHistory = Array(fenHistory.prefix(base.moveCount + 1))
        moveRecords.removeLast()          // canRetry ⇒ the retried move was recorded
        retryBase = nil                   // one rewind per snapshot
        lastMove = moves.last.flatMap { squares(fromUCI: $0) }
        selected = nil
        viewingPly = nil
        hint = nil
        lastVerdict = nil
        lastCoachNote = nil
        isCoaching = false
        gameOver = false
        resultText = nil
        gameSummary = nil
        isSummarizing = false
        status = "Your move — find a better one"
        refreshDests()
        refreshEval()
    }

    // MARK: End-of-game summary

    /// Stream the coach's written debrief of the finished game, built from the
    /// live-graded move records (no fresh engine work).
    private func startGameSummary() {
        guard coachEnabled, !moveRecords.isEmpty, gameSummary == nil, !isSummarizing else { return }
        let facts = CoachPromptBuilder.playGameFactsText(
            result: resultText ?? "The game is over.",
            playerSide: playerIsWhite ? .white : .black,
            opening: opening?.name, records: moveRecords)
        isSummarizing = true
        let gen = moveGen
        Task {
            defer { if gen == moveGen { isSummarizing = false } }
            do {
                let stream = try coach.summaryStream(facts: facts)
                for try await partial in stream {
                    guard gen == moveGen else { return }
                    gameSummary = partial
                }
            } catch {
                // No debrief — the result banner still stands.
            }
        }
    }

    /// Play the engine's reply and return its SAN (nil when no reply was made), so
    /// the coach note can read the opponent's move.
    @discardableResult
    private func engineReply() async -> String? {
        guard !gameOver else { return nil }
        engineThinking = true
        defer { engineThinking = false }
        var replySAN: String?
        do {
            if let reply = try await EnginePool.shared.playMove(fen: fen, depth: 12, skill: skill),
               let next = ChessLogic.fen(afterMove: reply, fromFEN: fen) {
                let fromFEN = fen
                fen = next
                moves.append(reply)
                replySAN = ChessLogic.san(fromUCI: reply, inFEN: fromFEN) ?? reply
                sanMoves.append(replySAN!)
                fenHistory.append(next)
                lastMove = squares(fromUCI: reply)
                hint = nil   // the position changed under any showing hint
                refreshDests()
                refreshEval()
                updateOpening(afterFEN: next)
                _ = checkGameOver(youMoved: false)
            }
        } catch {
            // engine hiccup — leave it the user's move
        }
        if !gameOver { status = "Your move" }
        return replySAN
    }

    /// Refine the live opening name after a ply. The book lookup is a dictionary hit,
    /// but the book itself is built lazily on first use (~3.7k line replays), so the
    /// work runs off the main actor and only a *hit* is written back (deepest-match).
    private func updateOpening(afterFEN newFEN: String) {
        Task.detached(priority: .utility) {
            guard let hit = Openings.match(fen: newFEN) else { return }
            await MainActor.run { self.opening = hit }
        }
    }

    /// The opening fact line for coach prompts, when a named line has been reached.
    private var openingFacts: String? {
        CoachPromptBuilder.openingFactsText(name: opening?.name, eco: opening?.eco)
    }

    /// The short written coach note for the move you just played. Streams in after
    /// the verdict chip so the user sees text appear instead of waiting for the whole
    /// paragraph. Reuses `moveReport` (no re-analysis) and runs one analysis of the
    /// live position; both are passed to the coach so it does NO engine work itself.
    ///
    /// Runs after the engine's reply, so `fen` is the live position with you to move
    /// again — every engine number the coach sees is then from YOUR perspective, and
    /// `playerSide` tells it which colour "you" are so it never confuses you with the
    /// engine.
    private func streamCoachNote(fromFEN: String, uci: String, moveReport: EngineLineReport?,
                                 opponentReplySAN: String? = nil, gen: Int? = nil) async {
        guard coachEnabled, let mv = moveReport?.move else { return }
        let san = ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci
        // The engine's grade (the same one shown on the chip) is authoritative. The
        // coach EXPLAINS the reasoning behind THAT grade, using its exact wording —
        // it never upgrades or downgrades it (an inaccuracy stays an inaccuracy, not
        // a "mistake").
        let cls = mv.classification.lowercased()
        let better = mv.isEngineBest ? nil : mv.betterMoveSAN
        let win = "\(Int(mv.winBefore.rounded()))% to \(Int(mv.winAfter.rounded()))%"
        var facts = "- The engine grades your move \(san) as: \(cls) (already shown to the user — do not restate it)."
        switch cls {
        case "best":
            facts += " It is the engine's top choice. In a few words, say what makes it strong."
        case "good":
            facts += " In a few words, say what makes it solid."
        case "inaccuracy":
            facts += " Winning chances slipped from \(win)."
            if let b = better { facts += " The more accurate move was \(b)." }
            facts += " Go straight to the reason — what \(better ?? "the better move") achieves or what \(san) slightly misses."
        case "mistake":
            facts += " Winning chances dropped from \(win)."
            if let b = better { facts += " The stronger move was \(b)." }
            facts += " Go straight to the reason — what \(san) allows or misses."
        case "blunder":
            facts += " Winning chances fell sharply from \(win)."
            if let b = better { facts += " A much stronger move was \(b)." }
            facts += " Go straight to the reason — what \(san) loses or allows."
        default:
            if let b = better { facts += " The engine prefers \(b)." }
        }
        // The opponent's actual reply, so the note ends with what to watch for next —
        // "the opponent may be trying to…" is the half of coaching the chip can't show.
        var question = "In one or two sentences, explain the reasoning behind the engine's grade of my move \(san)."
        if let reply = opponentReplySAN {
            facts += "\n- The opponent then replied \(reply)."
            question += " Then, in one more short sentence, tell me what the opponent's reply \(reply) is trying to do."
        }
        do {
            let stream = try await coach.answerStream(
                question: question,
                lastMove: uci, moveFen: fromFEN,
                playerSide: playerIsWhite ? .white : .black,
                openingFacts: openingFacts,
                moveFacts: facts,
                system: CoachPromptBuilder.moveNoteInstructions, depth: GCConfig.liveDepth)
            for try await partial in stream {
                if let gen, gen != moveGen { return }   // retried/new game mid-stream
                lastCoachNote = partial
            }
        } catch {
            // Leave the note empty; the engine verdict chip still stands on its own.
        }
    }

    // MARK: Ask the coach (free-form chat)

    /// Transcript of the Play-mode coach chat (role: "user"/"coach").
    public var chat: [(role: String, text: String)] = []
    /// True while a chat answer is being generated.
    public var isAsking: Bool = false

    /// Ask the coach a free-form question about the position you're looking at. The
    /// answer streams into the transcript. Grounded in engine facts and your colour.
    public func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, coachEnabled, !isAsking else { return }
        chat.append((role: "user", text: q))
        chat.append((role: "coach", text: ""))       // placeholder to stream into
        let idx = chat.count - 1
        isAsking = true
        defer { isAsking = false }
        let position = displayFEN
        do {
            let stream = try await coach.answerStream(
                question: q, fen: position,
                playerSide: playerIsWhite ? .white : .black,
                openingFacts: openingFacts,
                depth: GCConfig.liveDepth)
            for try await partial in stream where chat.indices.contains(idx) {
                chat[idx].text = partial
            }
        } catch let e as CoachError {
            if chat.indices.contains(idx) { chat[idx].text = e.message }
        } catch {
            if chat.indices.contains(idx) { chat[idx].text = error.localizedDescription }
        }
        if chat.indices.contains(idx), chat[idx].text.isEmpty {
            chat[idx].text = "I couldn't answer that one — try rephrasing."
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
            startGameSummary()
            return true
        case .stalemate:
            gameOver = true
            resultText = "Stalemate — it's a draw."
            status = resultText!
            startGameSummary()
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
