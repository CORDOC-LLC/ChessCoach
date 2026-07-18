//  CoachOrchestrator.swift
//  Picks the live coach backend (U16) and ties the engine → facts → prompt → model
//  flow together — the on-device equivalent of the source's `claude_bridge.ask()` /
//  `coach_summary_ai()`. Backends are tried in priority order; the first non-
//  unavailable one wins. When none is available, the UI hides chat and keeps the
//  engine-only review.
//
//  Every method that reaches a backend (`answer`, `answerStream`, `summaryStream`,
//  `gameSummary`) opens with `ProEntitlementStore.shared.requireProOrThrow()` --
//  the single, uniform Pro-entitlement gate (see that method's header). This is
//  the one interception point for ALL coach call sites (chat, hint rationale,
//  per-move notes, end-of-game summary), so callers (`PlayViewModel`,
//  `BoardScannerView`) don't each need their own check -- they only need to
//  catch `ProRequiredError` and trigger their paywall presentation.

import Foundation

public final class CoachOrchestrator: Sendable {

    private let backends: [CoachLLM]
    private let engine: EnginePool

    /// Default priority: the managed, developer-hosted coach first (paid tier
    /// or, for now, local debug testing — see `ManagedCoachStore`), then Gemini
    /// when the user has set their own API key -- unless `CoachBackendPreference`
    /// explicitly says otherwise (see `active` below and that type's header).
    /// Both are network backends — on-device Foundation Models/Gemma were tried
    /// and dropped (quality wasn't good enough), so there is no local fallback
    /// tier. Each backend reports `.unavailable` when unconfigured, so this
    /// list is a transparent fallthrough — nothing changes until the user
    /// opts into one.
    ///
    /// Which backends are even IN the list depends on `BuildChannel` (local
    /// dev and TestFlight installs get both managed + Gemini BYOK, App Store
    /// production gets the managed subscription only) — see that type's
    /// header for the reasoning.
    public init(
        backends: [CoachLLM] = CoachOrchestrator.defaultBackends(),
        engine: EnginePool = .shared
    ) {
        self.backends = backends
        self.engine = engine
    }

    public static func defaultBackends(channel: BuildChannel = .current) -> [CoachLLM] {
        var backends: [CoachLLM] = []
        if channel.allowsManagedCoach { backends.append(ManagedCoach()) }
        if channel.allowsGeminiBYOK { backends.append(GeminiCoach()) }
        return backends
    }

    /// The backend that answers. On channels offering both the managed coach
    /// and Gemini BYOK (local, TestFlight), respects the user's explicit
    /// `CoachBackendPreference` -- see that type's header for why this can't
    /// just be a fixed priority order. Elsewhere (App Store production, or
    /// only one backend configured/available), falls back to "first backend
    /// that isn't unavailable".
    private var active: CoachLLM? {
        func isAvailable(_ backend: CoachLLM) -> Bool {
            if case .unavailable = backend.availability { return false }
            return true
        }
        if BuildChannel.current.allowsManagedCoach, BuildChannel.current.allowsGeminiBYOK,
           CoachBackendPreference.current() == .byok,
           let gemini = backends.first(where: { $0 is GeminiCoach }), isAvailable(gemini) {
            return gemini
        }
        return backends.first(where: isAvailable)
    }

    /// State for the UI: which backend will answer, or why none can.
    public var availability: CoachAvailability {
        active?.availability ?? .unavailable(reason: "No coach is configured.")
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
        openingFacts: String? = nil,
        currentFacts: String? = nil,
        moveFacts: String? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        system: String? = nil,
        sessionID: String? = nil,
        depth: Int = GCConfig.defaultDepth
    ) async throws -> CoachReply {
        try await ProEntitlementStore.shared.requireProOrThrow()
        guard let backend = active else {
            throw CoachError("The on-device coach isn't available on this device. The engine review still works.")
        }
        let prompt = try await composePrompt(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen, playerSide: playerSide,
            openingFacts: openingFacts, currentFacts: currentFacts, moveFacts: moveFacts,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
        return try await backend.generate(
            system: system ?? CoachPromptBuilder.chatInstructions, prompt: prompt, sessionID: sessionID
        )
    }

    /// Streaming variant of `answer`: yields the cumulative text so the UI can show
    /// the answer fill in. Pass `currentFacts`/`moveFacts` to reuse engine analysis
    /// the caller already ran (skips the engine work here).
    public func answerStream(
        question: String,
        fen: String? = nil,
        lastMove: String? = nil,
        moveFen: String? = nil,
        playerSide: CoachSide? = nil,
        openingFacts: String? = nil,
        currentFacts: String? = nil,
        moveFacts: String? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        system: String? = nil,
        sessionID: String? = nil,
        depth: Int = GCConfig.defaultDepth
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await ProEntitlementStore.shared.requireProOrThrow()
        guard let backend = active else {
            throw CoachError("The on-device coach isn't available on this device. The engine review still works.")
        }
        let prompt = try await composePrompt(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen, playerSide: playerSide,
            openingFacts: openingFacts, currentFacts: currentFacts, moveFacts: moveFacts,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
        return backend.stream(
            system: system ?? CoachPromptBuilder.chatInstructions, prompt: prompt, sessionID: sessionID
        )
    }

    /// Build the grounded prompt. Computes engine facts only for the parts the caller
    /// didn't already supply (`currentFacts`/`moveFacts` overrides).
    private func composePrompt(
        question: String, fen: String?, lastMove: String?, moveFen: String?,
        playerSide: CoachSide?, openingFacts: String?, currentFacts: String?, moveFacts: String?,
        profileFacts: String?, speedContext: String?, depth: Int
    ) async throws -> String {
        let moveAtCurrent = (lastMove != nil) && (moveFen == nil || moveFen == fen)

        var current = currentFacts
        if current == nil, let fen {
            let report = try? await EngineLine.evaluate(
                fen: fen, move: moveAtCurrent ? lastMove : nil, depth: depth, multipv: 3, engine: engine
            )
            current = report.flatMap { CoachPromptBuilder.engineFactsText($0.coachInfo) }
        }

        var move = moveFacts
        if move == nil, let lastMove, !moveAtCurrent, let moveFen {
            let report = try? await EngineLine.evaluate(
                fen: moveFen, move: lastMove, depth: depth, multipv: 3, engine: engine
            )
            move = report.flatMap { CoachPromptBuilder.engineFactsText($0.coachInfo) }
        }

        return CoachPromptBuilder.chatPrompt(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen,
            playerSide: playerSide, openingFacts: openingFacts,
            currentFacts: current, moveFacts: move,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
    }

    /// Streaming end-of-game summary from a ready-made facts block (Play mode's
    /// live-graded games). Same persona as `gameSummary`, no engine work.
    public func summaryStream(facts: String) async throws -> AsyncThrowingStream<String, Error> {
        try await ProEntitlementStore.shared.requireProOrThrow()
        guard let backend = active else {
            throw CoachError("The on-device coach isn't available on this device.")
        }
        return backend.stream(
            system: CoachPromptBuilder.summaryInstructions,
            prompt: "This game's facts:\n" + facts, sessionID: nil
        )
    }

    /// A written end-of-game summary, grounded in pre-computed game facts.
    /// Mirrors `coach_summary_ai()`.
    public func gameSummary(_ input: CoachGameInput, profileFacts: String? = nil) async throws -> String {
        try await ProEntitlementStore.shared.requireProOrThrow()
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
