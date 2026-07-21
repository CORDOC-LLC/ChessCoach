//  CoachOrchestrator.swift
//  Ties the engine -> structured facts -> `/api/coach` flow together -- the
//  on-device equivalent of the source's `claude_bridge.ask()` /
//  `coach_summary_ai()`.
//
//  Every method that reaches the backend (`answer`, `answerStream`,
//  `summaryStream`, `gameSummary`) opens with
//  `ProEntitlementStore.shared.requireProOrThrow()` -- the single, uniform
//  Pro-entitlement gate (see that method's header). This is the one
//  interception point for ALL coach call sites (chat, hint rationale,
//  per-move notes, end-of-game summary), so callers (`PlayViewModel`,
//  `BoardScannerView`) don't each need their own check -- they only need to
//  catch `ProRequiredError` and trigger their paywall presentation.
//
//  Plan 2026-07-21-002 (U1/KTD-2/KTD-3): this used to format engine facts
//  into finished `{system, prompt}` text (`CoachPromptBuilder.chatPrompt`)
//  and hand it to whichever of several `CoachLLM` backends (`ManagedCoach`,
//  `GeminiCoach` BYOK) was active. The persona text is gone from this
//  open-source client now: `composePrompt` became `buildChatFacts`, which
//  assembles the SAME already-gathered structured data (engine facts via
//  `EngineLine.evaluate`, opening/profile/speed context) into a facts
//  payload, and `ManagedCoach` -- now the only backend -- sends it as JSON.
//  The gateway assembles the actual prompt server-side and never returns it.

import Foundation

public final class CoachOrchestrator: Sendable {

    private let coach: ManagedCoach
    private let engine: EnginePool
    /// Overridable so tests can force the Pro-entitlement gate to actually
    /// throw (`.appStore`) without needing a real distribution channel --
    /// mirrors `WeaknessReportClient.generateReport(channel:)`'s pattern.
    private let channel: BuildChannel

    public init(
        coach: ManagedCoach = ManagedCoach(),
        engine: EnginePool = .shared,
        channel: BuildChannel = .current
    ) {
        self.coach = coach
        self.engine = engine
        self.channel = channel
    }

    /// State for the UI: whether the managed coach is configured.
    public var availability: CoachAvailability { coach.availability }

    private func requireAvailable() throws {
        if case .unavailable = coach.availability {
            throw CoachError("The on-device coach isn't available on this device. The engine review still works.")
        }
    }

    /// Answer a position question, grounded in freshly-computed engine facts.
    /// `fen` is the board being viewed; `lastMove`/`moveFen` are the move in question
    /// and where it was played from. Mirrors `claude_bridge.ask()`.
    ///
    /// `currentFacts`/`moveFacts` let a caller that already ran its own engine
    /// analysis (e.g. `PlayViewModel.requestHint`) hand over the resulting
    /// `CoachLineInfo` directly, skipping a redundant `EngineLine.evaluate`
    /// call here. `kind` selects the gateway persona: `.chat` (default) or
    /// `.moveNote` for the terse per-move reaction (see
    /// `PlayViewModel.streamCoachNote`, the one call site that sets it).
    public func answer(
        question: String,
        fen: String? = nil,
        lastMove: String? = nil,
        moveFen: String? = nil,
        playerSide: CoachSide? = nil,
        openingFacts: String? = nil,
        currentFacts: CoachLineInfo? = nil,
        moveFacts: CoachLineInfo? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        kind: CoachRequestKind = .chat,
        sessionID: String? = nil,
        depth: Int = GCConfig.defaultDepth
    ) async throws -> CoachReply {
        try await ProEntitlementStore.shared.requireProOrThrow(channel: channel)
        try requireAvailable()
        let facts = try await buildChatFacts(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen, playerSide: playerSide,
            openingFacts: openingFacts, currentFacts: currentFacts, moveFacts: moveFacts,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
        return try await coach.generate(kind: kind, facts: facts, sessionID: sessionID)
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
        currentFacts: CoachLineInfo? = nil,
        moveFacts: CoachLineInfo? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        kind: CoachRequestKind = .chat,
        sessionID: String? = nil,
        depth: Int = GCConfig.defaultDepth
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await ProEntitlementStore.shared.requireProOrThrow(channel: channel)
        try requireAvailable()
        let facts = try await buildChatFacts(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen, playerSide: playerSide,
            openingFacts: openingFacts, currentFacts: currentFacts, moveFacts: moveFacts,
            profileFacts: profileFacts, speedContext: speedContext, depth: depth
        )
        return coach.stream(kind: kind, facts: facts, sessionID: sessionID)
    }

    /// Build the facts payload sent to `/api/coach` for `kind: .chat`/`.moveNote`.
    /// Computes engine facts only for the parts the caller didn't already supply
    /// (`currentFacts`/`moveFacts` overrides) -- same reuse contract as before,
    /// just handing back a `CoachLineInfo` (structured) instead of formatted text.
    private func buildChatFacts(
        question: String, fen: String?, lastMove: String?, moveFen: String?,
        playerSide: CoachSide?, openingFacts: String?,
        currentFacts: CoachLineInfo?, moveFacts: CoachLineInfo?,
        profileFacts: String?, speedContext: String?, depth: Int
    ) async throws -> ChatFacts {
        let moveAtCurrent = (lastMove != nil) && (moveFen == nil || moveFen == fen)

        var current = currentFacts
        if current == nil, let fen {
            let report = try? await EngineLine.evaluate(
                fen: fen, move: moveAtCurrent ? lastMove : nil, depth: depth, multipv: 3, engine: engine
            )
            current = report?.coachInfo
        }

        var move = moveFacts
        if move == nil, let lastMove, !moveAtCurrent, let moveFen {
            let report = try? await EngineLine.evaluate(
                fen: moveFen, move: lastMove, depth: depth, multipv: 3, engine: engine
            )
            move = report?.coachInfo
        }

        return ChatFacts(
            question: question, fen: fen, lastMove: lastMove, moveFen: moveFen,
            playerSide: playerSide, openingName: openingFacts, openingEco: nil,
            profileFacts: profileFacts, speedContext: speedContext,
            current: current, move: move, depth: depth
        )
    }

    /// Streaming end-of-game summary for a live Play game (`PlayViewModel`) --
    /// no engine work, `records` are already engine-graded live.
    public func summaryStream(_ input: CoachPlayGameInput) async throws -> AsyncThrowingStream<String, Error> {
        try await ProEntitlementStore.shared.requireProOrThrow(channel: channel)
        try requireAvailable()
        let facts = SummaryPlayFacts(
            result: input.result, playerSide: input.playerSide,
            opening: input.opening, records: input.records
        )
        return coach.stream(kind: .summary, facts: facts, sessionID: nil)
    }

    /// A written end-of-game summary for an imported/analyzed game
    /// (`ReviewViewModel`), grounded in pre-computed game facts. Mirrors
    /// `coach_summary_ai()`.
    ///
    /// `profileFacts` (cross-game history) has no home in the gateway's
    /// `summary` facts schema (KTD-5 -- ported 1:1 from the existing Swift
    /// structs, none of which carry it) -- kept as a parameter so this
    /// signature stays unchanged (R3), but it's currently unused; see this
    /// unit's report for the follow-up.
    public func gameSummary(_ input: CoachGameInput, profileFacts: String? = nil) async throws -> String {
        try await ProEntitlementStore.shared.requireProOrThrow(channel: channel)
        try requireAvailable()
        let facts = SummaryImportedFacts(
            white: input.white, black: input.black, result: input.result, opening: input.opening,
            speed: input.speed, player: input.player, accuracyWhite: input.accuracyWhite,
            accuracyBlack: input.accuracyBlack, mistakes: input.mistakes
        )
        let reply = try await coach.generate(kind: .summary, facts: facts, sessionID: nil)
        return reply.answer
    }
}

// MARK: - Wire facts payloads (matches chesscoach-gateway's /api/coach `facts` shapes)

/// `facts` for `kind: "chat"`/`kind: "moveNote"` requests.
private struct ChatFacts: Encodable, Sendable {
    var question: String
    var fen: String?
    var lastMove: String?
    var moveFen: String?
    var playerSide: CoachSide?
    var openingName: String?
    var openingEco: String?
    var profileFacts: String?
    var speedContext: String?
    var current: CoachLineInfo?
    var move: CoachLineInfo?
    var depth: Int
}

/// Structured inputs for a live Play game's end-of-game summary -- the
/// domain-level equivalent of `CoachGameInput` for Play mode (one known
/// accuracy: the user's own, graded move-by-move as the game was played).
public struct CoachPlayGameInput: Sendable, Equatable {
    public var result: String
    public var playerSide: CoachSide
    public var opening: String?
    public var records: [CoachPromptBuilder.PlayMoveRecord]
    public init(result: String, playerSide: CoachSide, opening: String?,
                records: [CoachPromptBuilder.PlayMoveRecord]) {
        self.result = result; self.playerSide = playerSide
        self.opening = opening; self.records = records
    }
}

/// `facts` for `kind: "summary"` requests from Play mode (`source: "play"`).
private struct SummaryPlayFacts: Encodable, Sendable {
    let source = "play"
    let result: String
    let playerSide: CoachSide
    let opening: String?
    let records: [CoachPromptBuilder.PlayMoveRecord]
}

/// `facts` for `kind: "summary"` requests from an imported/analyzed game
/// (`source: "imported"`).
private struct SummaryImportedFacts: Encodable, Sendable {
    let source = "imported"
    let white: String
    let black: String
    let result: String
    let opening: String?
    let speed: String
    let player: CoachSide
    let accuracyWhite: Double
    let accuracyBlack: Double
    let mistakes: [CoachFlaggedMove]
}
