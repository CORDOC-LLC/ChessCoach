//  CoachOrchestrator.swift
//  Picks the live coach backend (U16) and ties the engine → facts → prompt → model
//  flow together — the on-device equivalent of the source's `claude_bridge.ask()` /
//  `coach_summary_ai()`. Backends are tried in priority order; the first non-
//  unavailable one wins. When none is available, the UI hides chat and keeps the
//  engine-only review.

import Foundation

public final class CoachOrchestrator: Sendable {

    private let backends: [CoachLLM]
    private let engine: EnginePool

    /// Default priority: Foundation Models first; a Gemma backend can be appended by
    /// the app on devices without Apple Intelligence.
    public init(backends: [CoachLLM] = [FoundationModelsCoach()], engine: EnginePool = .shared) {
        self.backends = backends
        self.engine = engine
    }

    /// The first backend that isn't `.unavailable`, or nil.
    private var active: CoachLLM? {
        backends.first {
            if case .unavailable = $0.availability { return false }
            return true
        }
    }

    /// State for the UI: which backend will answer, or why none can.
    public var availability: CoachAvailability {
        active?.availability ?? .unavailable(reason: "No on-device coach is available.")
    }

    /// Answer a position question, grounded in freshly-computed engine facts.
    /// `fen` is the board being viewed; `lastMove`/`moveFen` are the move in question
    /// and where it was played from. Mirrors `claude_bridge.ask()`.
    public func answer(
        question: String,
        fen: String? = nil,
        lastMove: String? = nil,
        moveFen: String? = nil,
        playerSide: CoachSide? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        sessionID: String? = nil,
        depth: Int = GCConfig.defaultDepth
    ) async throws -> CoachReply {
        guard let backend = active else {
            throw CoachError("The on-device coach isn't available on this device. The engine review still works.")
        }

        let moveAtCurrent = (lastMove != nil) && (moveFen == nil || moveFen == fen)

        var currentFacts: String?
        if let fen {
            let report = try? await EngineLine.evaluate(
                fen: fen, move: moveAtCurrent ? lastMove : nil, depth: depth, multipv: 3, engine: engine
            )
            currentFacts = report.flatMap { CoachPromptBuilder.engineFactsText($0.coachInfo) }
        }

        var moveFacts: String?
        if let lastMove, !moveAtCurrent, let moveFen {
            let report = try? await EngineLine.evaluate(
                fen: moveFen, move: lastMove, depth: depth, multipv: 3, engine: engine
            )
            moveFacts = report.flatMap { CoachPromptBuilder.engineFactsText($0.coachInfo) }
        }

        let prompt = CoachPromptBuilder.chatPrompt(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen,
            playerSide: playerSide,
            currentFacts: currentFacts, moveFacts: moveFacts,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
        return try await backend.generate(
            system: CoachPromptBuilder.chatInstructions, prompt: prompt, sessionID: sessionID
        )
    }

    /// A written end-of-game summary, grounded in pre-computed game facts.
    /// Mirrors `coach_summary_ai()`.
    public func gameSummary(_ input: CoachGameInput, profileFacts: String? = nil) async throws -> String {
        guard let backend = active else {
            throw CoachError("The on-device coach isn't available on this device.")
        }
        var prompt = ""
        if let profileFacts {
            prompt += "The player's cross-game history is below — use it to point out a recurring "
                + "pattern only when this game genuinely shows one; otherwise ignore it.\n"
                + profileFacts + "\n\n"
        }
        prompt += "This game's facts:\n" + CoachPromptBuilder.gameFactsText(input)
        let reply = try await backend.generate(
            system: CoachPromptBuilder.summaryInstructions, prompt: prompt, sessionID: nil
        )
        return reply.answer
    }
}
