//  CoachOrchestratorTests.swift
//  Covers U16 (orchestrator routing + engine→facts→prompt wiring). Model output
//  itself is backend-dependent, so a mock backend echoes the (system, prompt)
//  it receives.

import Testing
@testable import GemmaChessCore

/// Records and echoes what the orchestrator hands a backend.
private final class MockCoach: CoachLLM {
    let state: CoachAvailability
    init(_ state: CoachAvailability) { self.state = state }
    var availability: CoachAvailability { state }
    func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        CoachReply(answer: "SYS::\(system)\n>>>\n\(prompt)", sessionID: "mock-1")
    }
}

private let blunderFEN = "rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2"

@Suite("Coach: orchestrator", .serialized)
struct CoachOrchestratorTests {

    @Test("picks the first available backend; reports its state")
    func backendSelection() {
        let o = CoachOrchestrator(backends: [
            MockCoach(.unavailable(reason: "no FM")),
            MockCoach(.gemini),
        ])
        #expect(o.availability == .gemini)
    }

    @Test("all-unavailable backends -> unavailable + answering throws")
    func allUnavailable() async {
        let o = CoachOrchestrator(backends: [MockCoach(.unavailable(reason: "x"))])
        if case .unavailable = o.availability {} else { Issue.record("expected unavailable") }
        await #expect(throws: CoachError.self) {
            _ = try await o.answer(question: "best move?", fen: blunderFEN, depth: 12)
        }
    }

    @Test("answer() grounds the prompt in real engine facts about the move in question")
    func groundsAnswerInEngineFacts() async throws {
        let o = CoachOrchestrator(backends: [MockCoach(.gemini)])
        let reply = try await o.answer(
            question: "Why is g4 bad here?",
            fen: blunderFEN, lastMove: "g4", moveFen: blunderFEN, depth: 12
        )
        // The mock echoed the composed (system, prompt): both the persona and the
        // engine-grounded verdict must be present.
        #expect(reply.answer.contains("TRUST it, do not recompute"))     // chat persona (system)
        #expect(reply.answer.contains("The move g4 is classified a blunder"))
        #expect(reply.answer.contains("User question: Why is g4 bad here?"))
        #expect(reply.sessionID == "mock-1")
    }

    @Test("gameSummary() grounds the prompt in the game facts + uses the summary persona")
    func gameSummaryGrounding() async throws {
        let o = CoachOrchestrator(backends: [MockCoach(.gemini)])
        let input = CoachGameInput(
            white: "alice", black: "bob", result: "1-0", opening: "Italian Game",
            speed: "blitz", player: .white, accuracyWhite: 92.7, accuracyBlack: 81.0,
            mistakes: [CoachFlaggedMove(moveNumber: 4, color: .white, moveSan: "Nf3",
                classification: "blunder", winBefore: 80.8, winAfter: 56.9, winSwing: 23.9,
                bestMoveSan: "c3", comment: "Allows a fork.")]
        )
        let summary = try await o.gameSummary(input, profileFacts: "You hang pieces in time trouble.")
        #expect(summary.contains("encouraging but honest chess coach"))   // summary persona
        #expect(summary.contains("Reviewing White. Accuracy: 92.7%"))
        #expect(summary.contains("cross-game history"))
        #expect(summary.contains("You hang pieces in time trouble."))
    }
}
