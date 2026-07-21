//  ReviewViewModel.swift
//  The single @Observable view model behind the review UI. It owns the analysed
//  session, the board cursor, the coach conversation, and the derived presentation
//  values (current FEN, arrows, verdict, eval). All chess/analysis work is delegated
//  to GemmaChessCore; this type only orchestrates and shapes data for the views.

import SwiftUI
import ChessKit

@MainActor
@Observable
public final class ReviewViewModel {

    // MARK: Stored state
    public var session: ReviewSession?
    public var currentNode: Int = 0
    public var isAnalyzing: Bool = false
    public var progress: Double = 0
    public var orientationIsWhite: Bool = true
    public var coachAvailability: CoachAvailability = .unavailable(reason: "Checking…")
    public var chat: [(role: String, text: String)] = []
    public var summaryText: String?
    public var errorText: String?
    public var personalize: Bool = false
    public var isAsking: Bool = false
    public var isSummarizing: Bool = false

    private let coach: CoachOrchestrator
    private var coachSessionID: String?

    public init(coach: CoachOrchestrator = CoachOrchestrator()) {
        self.coach = coach
        self.coachAvailability = coach.availability
    }

    // MARK: Derived

    public var orientation: BoardOrientation { orientationIsWhite ? .white : .black }

    public var currentTimelineNode: TimelineNode? {
        guard let s = session, s.timeline.indices.contains(currentNode) else { return nil }
        return s.timeline[currentNode]
    }

    public var currentFEN: String? { currentTimelineNode?.fen }

    public var nodeCount: Int { session?.timeline.count ?? 0 }

    public var winWhiteCurrent: Double { currentTimelineNode?.winWhite ?? 50 }

    /// Arrows for the current node: played move (gray), engine best (green, thick).
    public var boardArrows: [BoardArrow] {
        guard let node = currentTimelineNode else { return [] }
        var arrows: [BoardArrow] = []
        if let uci = node.moveUCI, let a = BoardArrow(uci: uci, color: .gray, thick: false) {
            arrows.append(a)
        }
        if let best = node.bestUCI, best != node.moveUCI,
           let a = BoardArrow(uci: best, color: .green, thick: true) {
            arrows.append(a)
        }
        return arrows
    }

    /// Squares of the move shown at the current node, for the board highlight.
    public var lastMoveSquares: (from: Square, to: Square)? {
        guard let uci = currentTimelineNode?.moveUCI, uci.count >= 4,
              let from = BoardGeometry.square(String(uci.prefix(2))),
              let to = BoardGeometry.square(String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }

    /// The full move review for the current node (my moves only), powering the verdict box.
    public var verdict: MoveReview? {
        guard let node = currentTimelineNode, let ply = node.ply else { return nil }
        return session?.allMoves.first { $0.ply == ply }
    }

    public var winValues: [Double] { session?.timeline.map { $0.winWhite } ?? [] }

    // MARK: Navigation

    public func goto(node: Int) {
        guard nodeCount > 0 else { return }
        currentNode = min(max(node, 0), nodeCount - 1)
    }
    public func next() { goto(node: currentNode + 1) }
    public func prev() { goto(node: currentNode - 1) }
    public func flip() { orientationIsWhite.toggle() }

    /// Jump to a mistake by its index into `session.mistakes` and land on the position
    /// just before the mistake was played.
    public func gotoMistake(index: Int) {
        guard var s = session, let result = s.gotoMistake(index) else { return }
        session = s
        // The mistake's `ply` is 1-based; the position *before* it is node `ply - 1`.
        goto(node: max(result.review.ply - 1, 0))
    }

    // MARK: Analysis

    public func analyze(pgn: String, player: String = "auto") async {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorText = "Paste a PGN first."; return }
        isAnalyzing = true
        progress = 0
        errorText = nil
        summaryText = nil
        chat = []
        coachSessionID = nil
        defer { isAnalyzing = false }

        if let cached = AnalysisCache.load(pgn: trimmed, player: player) {
            apply(session: cached)
            return
        }

        do {
            let result = try await GameAnalyzer.analyzeGame(
                pgn: trimmed,
                player: player,
                onProgress: { done, total in
                    Task { @MainActor in
                        self.progress = total > 0 ? Double(done) / Double(total) : 0
                    }
                })
            AnalysisCache.store(result)
            // Best-effort history record; never blocks the review.
            _ = HistoryStore().recordGame(result, identity: PlayerIdentity())
            apply(session: result)
        } catch let error as AnalysisError {
            errorText = error.message
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply(session s: ReviewSession) {
        session = s
        currentNode = 0
        orientationIsWhite = (s.player == "white")
        progress = 1
    }

    // MARK: Coach

    public func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        chat.append((role: "user", text: q))
        isAsking = true
        defer { isAsking = false }
        do {
            let node = currentTimelineNode
            let reply = try await coach.answer(
                question: q,
                fen: currentFEN,
                lastMove: node?.moveUCI,
                moveFen: currentFEN,
                playerSide: session.map { $0.player == "white" ? .white : .black },
                openingFacts: session.flatMap {
                    let name = $0.resolveOpening()
                    return name.isEmpty ? nil : name
                },
                profileFacts: personalize ? profileFacts() : nil,
                speedContext: session.map { "This game's time control is \($0.speed)." },
                sessionID: coachSessionID)
            coachSessionID = reply.sessionID
            chat.append((role: "coach", text: reply.answer))
        } catch let error as CoachError {
            chat.append((role: "coach", text: error.message))
        } catch {
            chat.append((role: "coach", text: error.localizedDescription))
        }
    }

    public func summarize() async {
        guard let s = session else { return }
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            let text = try await coach.gameSummary(
                buildCoachGameInput(s),
                profileFacts: personalize ? profileFacts() : nil)
            summaryText = text
        } catch let error as CoachError {
            errorText = error.message
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func buildCoachGameInput(_ s: ReviewSession) -> CoachGameInput {
        let side: CoachSide = s.player == "white" ? .white : .black
        let flagged = s.mistakes.map { m in
            CoachFlaggedMove(
                moveNumber: m.moveNumber,
                color: m.color == "white" ? .white : .black,
                moveSan: m.moveSAN,
                classification: m.classification,
                winBefore: m.winBefore,
                winAfter: m.winAfter,
                winSwing: m.winSwing,
                bestMoveSan: m.bestMoveSAN,
                comment: m.comment)
        }
        return CoachGameInput(
            white: s.headers["White"] ?? "?",
            black: s.headers["Black"] ?? "?",
            result: s.result,
            opening: s.resolveOpening(),
            speed: s.speed,
            player: side,
            accuracyWhite: s.accuracyWhite,
            accuracyBlack: s.accuracyBlack,
            mistakes: flagged)
    }

    /// Build the personalization facts string from stored history, if any.
    private func profileFacts() -> String? {
        let store = HistoryStore()
        guard let pid = store.listPlayers().first else { return nil }
        let profile = CoachingProfileBuilder.buildProfile(playerID: pid, store: store)
        return CoachingProfileBuilder.formatProfileForPrompt(profile)
    }
}
