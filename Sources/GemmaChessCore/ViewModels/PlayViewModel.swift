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

    /// Colour for a classification: best/good → theme accent, inaccuracy →
    /// theme highlight, mistake/blunder → fixed system colors (not theme-tied
    /// -- these read as warnings regardless of the active palette).
    public static func color(for classification: String, theme: Theme) -> Color {
        switch classification.lowercased() {
        case "best", "good": return theme.accentColor
        case "inaccuracy": return theme.accent2Color
        case "mistake": return .orange
        case "blunder": return .red
        default: return theme.accentColor
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

    /// How the finished game went for the user -- drives the game-over banner's
    /// icon/color. Derived from `resultText`'s own wording rather than tracked
    /// separately, since `checkGameOver`/`resign` already set it precisely.
    public var outcome: PlayOutcome? {
        guard gameOver, let resultText else { return nil }
        if resultText.contains("you win") { return .win }
        if resultText.contains("you lose") || resultText == "You resigned." { return .loss }
        return .draw
    }
    /// Lifetime win/loss/draw tally, shown in the game-over banner and Settings.
    /// Updated (and persisted) the instant a game actually ends.
    public private(set) var stats: PlayStats
    /// Set when a finished game crosses `ReviewPromptStore.shouldPrompt`'s
    /// threshold -- the view watches this to present `ReviewPromptView`,
    /// mirroring `LessonViewModel`/`OpeningTrainerViewModel`'s `showPaywall`
    /// pattern (plan U6/KTD-7).
    public var showReviewPrompt = false
    /// Opponent strength: Stockfish "Skill Level" 0–20.
    public var skill: Int = 6
    /// Opt-in "Human-like" opponent (plan R1/U1): while true and within
    /// `humanLikeBookPlyWindow`, engine replies are drawn from a randomly
    /// matching ECO book line instead of the engine's own top choice. Off by
    /// default; pushed in from `PlayDisplaySettings.humanLikeEnabled` by the view,
    /// mirroring `coachDisplayEnabled`.
    public var humanLikeEnabled: Bool = false
    /// How many plies (both sides combined) the Human-like book continuation is
    /// allowed to steer -- after this, replies always fall through to normal
    /// engine play regardless of whether a matching line still exists deeper,
    /// so the effect reads as "varied openings," not "the engine can't play
    /// its own game."
    public static let humanLikeBookPlyWindow = 8
    /// Whether the current toggle/skill combination is in the Human-like
    /// weighted-sampling band (plan U2/KTD-2) -- i.e. `engineReply()` will call
    /// `EnginePool.humanLikeMove` instead of `EnginePool.playMove` once past the
    /// opening-book window. Exposed as a pure, engine-free predicate so the
    /// threshold decision itself is directly unit-testable without a full engine
    /// round trip.
    var usesHumanLikeSampling: Bool { humanLikeEnabled && skill < EnginePool.lowSkillThreshold }
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

    // MARK: Best Moves (engine-only, free -- no coach/network involved)
    /// Structured engine verdict on the user's latest move.
    public var lastVerdict: MoveVerdict?
    /// The engine's top candidate moves (best first) for the position BEFORE the
    /// user's last move -- i.e. what Stockfish actually considered there, for
    /// comparison against the move played. Cleared on a new game/retry; not
    /// persisted (recomputed live, not needed for replay).
    public var topMoves: [EngineLineReport.SubLine] = []

    // MARK: Coach card (U7) -- the one piece that spends Gemini credits
    /// The coach's short "what to focus on" note for the latest move.
    public var lastCoachNote: String?
    /// The reason the last coach request failed (network error, missing
    /// config, "not entitled", etc.), so a misconfigured backend shows up as
    /// a specific message instead of just silence -- surfaced in the coach
    /// card whenever there's no note/summary to show instead. Cleared at the
    /// start of every new coach request.
    public var lastCoachError: String?

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
    /// Bumped by undo/new game so in-flight verdict/note/summary tasks abandon
    /// their writes instead of scribbling on the rewound game.
    private var moveGen = 0

    // MARK: Opening recognition
    /// The deepest named opening the game has reached so far (lichess chess-openings
    /// book), refined live after every ply. Never regresses: an out-of-book move
    /// keeps the last named line ("you left the London with …" still reads right).
    public var opening: Openings.Opening?

    // MARK: On-device persistence (resume + replay)
    /// Identity of the game being saved -- stable across the whole game so
    /// checkpoints overwrite the same file rather than accumulating one per move.
    public private(set) var gameID = UUID()
    private var startedAt = Date()
    /// The coach's per-move note, keyed by the 0-based ply index of the USER's
    /// move it explains. Mirrors `SavedGame.moveNotes`; `lastCoachNote` only ever
    /// holds the LATEST one, so replay (viewing an arbitrary past ply) needs this.
    private(set) var moveNotes: [Int: String] = [:]

    private var dests: [Square: [Square]] = [:]
    private let coach: CoachOrchestrator
    /// Where `SavedGame` checkpoints are written, and which UserDefaults tracks
    /// the in-progress game pointer -- both injectable so tests use a temp
    /// directory / scratch defaults instead of the real ones. Internal (not
    /// private) so tests can point `SavedGameStore` calls at the same values.
    let savedGamesBaseDir: URL
    let savedGamesDefaults: UserDefaults
    /// Where the lifetime win/loss/draw tally is persisted -- likewise injectable.
    let statsDefaults: UserDefaults
    /// Where finished Play games are folded into `HistoryStore` (Coach Weakness
    /// Report, plan U2) -- injectable so tests never touch the real
    /// Application Support directory or a shared `games.jsonl`.
    let historyBaseDir: URL?

    public init(
        coach: CoachOrchestrator = CoachOrchestrator(),
        savedGamesBaseDir: URL = SavedGameStore.defaultBaseDir,
        savedGamesDefaults: UserDefaults = .standard,
        statsDefaults: UserDefaults = .standard,
        historyBaseDir: URL? = nil
    ) {
        self.coach = coach
        self.coachAvailability = coach.availability
        self.savedGamesBaseDir = savedGamesBaseDir
        self.savedGamesDefaults = savedGamesDefaults
        self.statsDefaults = statsDefaults
        self.historyBaseDir = historyBaseDir
        self.stats = PlayStatsStore.current(defaults: statsDefaults)
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

    /// The coach's note for the ply at 0-based index `ply` (the user move it
    /// explains), or nil if none was recorded. Used when browsing history --
    /// live play instead follows `lastCoachNote`, which is always the latest.
    public func note(forPly ply: Int) -> String? { moveNotes[ply] }

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
            } catch let e as ProRequiredError {
                // Rationale is Pro-gated (see `CoachOrchestrator.answerStream`) --
                // the best-move arrow/SAN above already stand on their own; this
                // just says why the rationale line didn't fill in, distinctly
                // from a generic failure, so the UI can offer the paywall.
                if position == fen { lastCoachError = e.message }
            } catch {
                // No rationale — the arrows and SANs still stand on their own,
                // but the coach card (shared error slot) shows why it failed.
                if position == fen { lastCoachError = (error as? CoachError)?.message ?? error.localizedDescription }
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
        topMoves = []
        lastCoachNote = nil
        hint = nil
        opening = nil
        gameSummary = nil
        isSummarizing = false
        moveRecords = []
        moveGen += 1
        chat = []
        isAsking = false
        coachAvailability = coach.availability
        gameID = UUID()
        startedAt = Date()
        moveNotes = [:]
        refreshDests()
        refreshEval()
        let userToMoveNow = (ChessLogic.sideToMove(forFEN: startFEN) == .white) == asWhite
        if userToMoveNow {
            status = "Your move"
            persistCheckpoint()
        } else {
            status = "Engine is thinking…"
            let gen = moveGen
            Task {
                await engineReply()
                if gen == moveGen { persistCheckpoint() }
            }
        }
    }

    public func resign() {
        guard !gameOver else { return }
        gameOver = true
        resultText = "You resigned."
        status = resultText!
        startGameSummary()
        recordOutcome()
        persistCheckpoint()
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

        let moveNumber = moves.count / 2 + 1
        let userPly = moves.count   // this move's index, once appended below
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
        topMoves = []
        lastCoachNote = nil
        let gen = moveGen
        persistCheckpoint()   // save the user's move even if the app dies right after
        Task {
            // ONE analysis serves the verdict chip, the Best Moves top-3 list, and
            // the coach's move facts (this used to be analysed twice). multipv 3
            // gives the top-3 candidates the Best Moves card shows -- free, engine-
            // only, so it runs and updates regardless of whether the coach is on.
            let moveReport = try? await EngineLine.evaluate(
                fen: fromFEN, move: uci, depth: GCConfig.liveDepth, multipv: 3)
            guard gen == moveGen else { return }   // retried/new game while analysing
            topMoves = moveReport?.lines ?? []
            if let mv = moveReport?.move {
                let san = ChessLogic.san(fromUCI: uci, inFEN: fromFEN) ?? uci
                lastVerdict = MoveVerdict(
                    moveSAN: san, classification: mv.classification,
                    isBest: mv.isEngineBest, betterMoveSAN: mv.isEngineBest ? nil : mv.betterMoveSAN)
                moveRecords.append(CoachPromptBuilder.PlayMoveRecord(
                    moveNumber: moveNumber, san: san, classification: mv.classification,
                    winBefore: mv.winBefore, winAfter: mv.winAfter,
                    betterSan: mv.isEngineBest ? nil : mv.betterMoveSAN,
                    // `moveReport.lineUCI` is the engine's own best line for `fromFEN`
                    // (computed by this same analysis, above) -- its first move is
                    // exactly the "best move" UCI `Motifs.tagMotifs` needs later.
                    bestUCI: moveReport?.lineUCI.first))
            }
            let replySAN = await engineReply()
            guard gen == moveGen else { return }
            await streamCoachNote(fromFEN: fromFEN, uci: uci, moveReport: moveReport,
                                  opponentReplySAN: replySAN, userPly: userPly, gen: gen)
            if gen == moveGen { isCoaching = false; persistCheckpoint() }
        }
    }

    // MARK: Undo (unlimited -- this app is about learning, not defending a score)

    /// True whenever there's a move to take back: the engine isn't mid-reply and
    /// you're not browsing history. Unlike the old "retry", this has no
    /// classification gate and no one-use limit — undo any move, as many times
    /// in a row as you like, all the way back to the start of the game. Works
    /// after game over too — undoing the losing move un-ends the game.
    public var canUndo: Bool {
        !moves.isEmpty && !engineThinking && !isViewingHistory
    }

    /// Take back the last full round — your move, plus the engine's reply if it
    /// got to make one (a mate/stalemate on your own move ends the game before
    /// the engine replies, so there's nothing of its to pop). Callable
    /// repeatedly; any in-flight coach work for the undone round is abandoned.
    public func undoLastMove() {
        guard canUndo else { return }
        moveGen += 1
        if !moves.isEmpty, !isUserPly(moves.count - 1) {
            popLastPly(wasUserMove: false)   // the engine's reply
        }
        if !moves.isEmpty {
            popLastPly(wasUserMove: true)    // your move
        }
        lastMove = moves.last.flatMap { squares(fromUCI: $0) }
        selected = nil
        viewingPly = nil
        hint = nil
        lastVerdict = nil
        topMoves = []
        lastCoachNote = nil
        isCoaching = false
        gameOver = false
        resultText = nil
        gameSummary = nil
        isSummarizing = false
        status = "Your move"
        refreshDests()
        refreshEval()
        persistCheckpoint()
    }

    /// Whether ply `i` (0-based index into `moves`) was played by the user,
    /// as opposed to the engine.
    private func isUserPly(_ i: Int) -> Bool { (i % 2 == 0) == playerIsWhite }

    /// Remove the most recent ply from every parallel array. `wasUserMove`
    /// controls whether the matching `moveRecords`/`moveNotes` entry (which
    /// only exists for the user's own moves) is trimmed too.
    private func popLastPly(wasUserMove: Bool) {
        guard !moves.isEmpty else { return }
        let poppedIndex = moves.count - 1
        moves.removeLast()
        sanMoves.removeLast()
        fenHistory.removeLast()
        fen = fenHistory.last ?? Self.startFEN
        if wasUserMove {
            if !moveRecords.isEmpty { moveRecords.removeLast() }
            moveNotes.removeValue(forKey: poppedIndex)
        }
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
        lastCoachError = nil
        let gen = moveGen
        Task {
            defer { if gen == moveGen { isSummarizing = false } }
            do {
                let stream = try await coach.summaryStream(facts: facts)
                for try await partial in stream {
                    guard gen == moveGen else { return }
                    gameSummary = partial
                }
                if gen == moveGen { persistCheckpoint() }
            } catch let e as ProRequiredError {
                // The debrief is Pro-gated (see `CoachOrchestrator.summaryStream`) --
                // the result banner still stands on its own.
                guard gen == moveGen else { return }
                lastCoachError = e.message
            } catch {
                // No debrief — the result banner still stands, but say why.
                guard gen == moveGen else { return }
                lastCoachError = (error as? CoachError)?.message ?? error.localizedDescription
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
            let reply: String?
            if let bookUCI = humanLikeBookReplyUCI() {
                reply = bookUCI
            } else if usesHumanLikeSampling {
                // U2/KTD-2: out of book (or book toggle off for this ply), but still
                // in the human-like low-skill band -- weighted-sample among the
                // engine's own top candidates instead of always its single best move.
                reply = try await EnginePool.shared.humanLikeMove(fen: fen, depth: 12, skill: skill)
            } else {
                reply = try await EnginePool.shared.playMove(fen: fen, depth: 12, skill: skill)
            }
            if let reply,
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

    /// The Human-like opponent's opening-book continuation for the engine's reply
    /// (plan U1/KTD-1), or nil when it doesn't apply -- the toggle is off, the game
    /// is past the bounded book-ply window, or no vendored ECO line's SAN prefix
    /// matches `sanMoves` (out of book). `nil` means "fall through to normal engine
    /// play unchanged," which is also what happens if the matched SAN can't be
    /// converted back to UCI for the current position (should not happen for a
    /// real book line, but never crash/lock up a game over it).
    private func humanLikeBookReplyUCI() -> String? {
        guard humanLikeEnabled, sanMoves.count < Self.humanLikeBookPlyWindow else { return nil }
        guard let bookSAN = Openings.bookContinuation(afterSAN: sanMoves) else { return nil }
        return ChessLogic.uci(fromSAN: bookSAN, inFEN: fen)
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

    // MARK: On-device persistence (resume + replay)

    /// The in-flight (or last) checkpoint write -- each new checkpoint awaits
    /// the previous one so writes stay ordered. See `persistCheckpoint`.
    private var persistWriteTask: Task<Void, Never>?

    /// Awaits any in-flight checkpoint write. Tests use this to read the
    /// saved file deterministically; production code never needs it (the
    /// chained writes guarantee the newest snapshot always lands last).
    public func flushPendingSave() async {
        await persistWriteTask?.value
    }

    /// Snapshot the current game to disk. Called after every state-changing event
    /// (a move, a coach note landing, game over) so a killed app loses at most the
    /// in-flight step, never the whole game. Cheap: a small per-game JSON file, no
    /// network involved -- see `SavedGame`'s header.
    private func currentSavedGameSnapshot() -> SavedGame {
        SavedGame(
            id: gameID, startedAt: startedAt, updatedAt: Date(), playerIsWhite: playerIsWhite,
            startFEN: fenHistory.first ?? Self.startFEN, moves: moves, sanMoves: sanMoves,
            fenHistory: fenHistory, skill: skill, isGameOver: gameOver, resultText: resultText,
            openingName: opening?.name, openingECO: opening?.eco,
            moveNotes: moveNotes, gameSummary: gameSummary, moveRecords: moveRecords
        )
    }

    private func persistCheckpoint() {
        let game = currentSavedGameSnapshot()
        let dir = savedGamesBaseDir
        // Encode + write off the main actor: this fires on every ply, inside
        // the same call stack as the user's tap and the move animation, and a
        // synchronous whole-game JSON encode + atomic file write there was a
        // per-move main-thread hitch. Chained on the previous write so
        // checkpoints land in order (last write must be the newest snapshot).
        let previous = persistWriteTask
        persistWriteTask = Task.detached(priority: .utility) {
            await previous?.value
            try? SavedGameStore.save(game, baseDir: dir)
        }
        if gameOver {
            // A finished game is replay-only from here -- stop offering it as "Resume".
            if SavedGameStore.inProgressGameID(defaults: savedGamesDefaults) == gameID {
                SavedGameStore.setInProgressGameID(nil, defaults: savedGamesDefaults)
            }
        } else {
            SavedGameStore.setInProgressGameID(gameID, defaults: savedGamesDefaults)
        }
    }

    /// Reconstruct full live state from a saved game -- for "Resume" (an unfinished
    /// game continues exactly where it left off, engine replying if it's its turn)
    /// or opening a finished game for replay (browsable via `viewTo`, no further
    /// moves possible since `tap` already refuses them once `gameOver` is true).
    public func load(_ saved: SavedGame) {
        moveGen += 1   // abandon any in-flight task tied to whatever was live before
        gameID = saved.id
        startedAt = saved.startedAt
        playerIsWhite = saved.playerIsWhite
        moves = saved.moves
        sanMoves = saved.sanMoves
        fenHistory = saved.fenHistory
        fen = saved.fenHistory.last ?? saved.startFEN
        skill = saved.skill
        gameOver = saved.isGameOver
        resultText = saved.resultText
        opening = saved.openingName.map { Openings.Opening(eco: saved.openingECO ?? "", name: $0) }
        moveNotes = saved.moveNotes
        lastCoachNote = saved.moves.indices.last.flatMap { saved.moveNotes[$0] }
        gameSummary = saved.gameSummary
        moveRecords = saved.moveRecords
        lastVerdict = nil    // not persisted -- the chip is a live-move-only affordance
        topMoves = []        // likewise
        hint = nil
        selected = nil
        viewingPly = nil
        isCoaching = false
        isSummarizing = false
        chat = []
        isAsking = false
        coachAvailability = coach.availability
        refreshDests()
        refreshEval()
        if saved.isGameOver {
            status = saved.resultText ?? "Game over"
        } else {
            SavedGameStore.setInProgressGameID(saved.id, defaults: savedGamesDefaults)
            if userToMove {
                status = "Your move"
            } else {
                status = "Engine is thinking…"
                let gen = moveGen
                Task {
                    await engineReply()
                    if gen == moveGen { persistCheckpoint() }
                }
            }
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
                                 opponentReplySAN: String? = nil, userPly: Int? = nil, gen: Int? = nil) async {
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
        lastCoachError = nil
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
            if let userPly, let gen, gen == moveGen, let note = lastCoachNote, !note.isEmpty {
                moveNotes[userPly] = note
            }
        } catch let e as ProRequiredError {
            // The note is Pro-gated (see `CoachOrchestrator.answerStream`) -- the
            // engine verdict chip still stands on its own.
            if let gen, gen != moveGen { return }
            lastCoachError = e.message
        } catch {
            // The engine verdict chip still stands on its own -- but surface
            // WHY the note didn't come through (missing config, not entitled,
            // network error) instead of leaving the card silently blank.
            if let gen, gen != moveGen { return }
            lastCoachError = (error as? CoachError)?.message ?? error.localizedDescription
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
        } catch let e as ProRequiredError {
            // Chat is Pro-gated (see `CoachOrchestrator.answerStream`) -- surface
            // the reason inline so the user knows to subscribe, not that
            // something broke.
            if chat.indices.contains(idx) { chat[idx].text = e.message }
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
            recordOutcome()
            persistCheckpoint()
            return true
        case .stalemate:
            gameOver = true
            resultText = "Stalemate — it's a draw."
            status = resultText!
            startGameSummary()
            recordOutcome()
            persistCheckpoint()
            return true
        default:
            return false
        }
    }

    /// Tallies the just-finished game into the lifetime win/loss/draw stats,
    /// and -- new for the Coach Weakness Report (plan U2) -- folds the game
    /// into `HistoryStore` so it feeds the same coaching profile Review mode's
    /// imported games already do. Called from `checkGameOver`/`resign` exactly
    /// once per real ending -- never from `load(_:)`, so reopening an
    /// already-finished saved game for replay doesn't double-count it or
    /// re-append a duplicate history record.
    private func recordOutcome() {
        guard let outcome else { return }
        stats = PlayStatsStore.record(outcome, defaults: statsDefaults)
        let history = HistoryStore(baseDir: historyBaseDir)
        if let record = history.buildGameRecord(from: currentSavedGameSnapshot(), identity: PlayerIdentity()) {
            history.appendRecord(record)
        }
        checkReviewPrompt()
    }

    /// Checked after every finished game -- one of the two engagement events
    /// `ReviewPromptStore.shouldPrompt` gates on (the other is a completed
    /// lesson, checked from `LessonsView`). `lessonsCompleted` is computed
    /// here rather than read from a store-owned convenience, per U5's
    /// Approach: `ReviewPromptStore` takes caller-supplied totals instead of
    /// duplicating `LessonProgressStore`/`PlayStatsStore`'s own counters.
    private func checkReviewPrompt() {
        let lessonsCompleted = LessonCatalog.allLessons.filter {
            LessonProgressStore.progress(for: $0.id) == .completed
        }.count
        if ReviewPromptStore.shouldPrompt(lessonsCompleted: lessonsCompleted, gamesPlayed: stats.totalGames) {
            showReviewPrompt = true
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
