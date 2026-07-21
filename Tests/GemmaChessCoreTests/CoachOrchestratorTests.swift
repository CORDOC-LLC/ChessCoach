//  CoachOrchestratorTests.swift
//  Covers the orchestrator's routing + engine -> facts wiring (plan
//  2026-07-21-002, U1). `CoachOrchestrator` now depends on `ManagedCoach`
//  concretely -- these tests drive it via `ManagedCoach.mock(...)` (a mock
//  URLProtocol, see `TestSupport.swift`) and assert on the JSON body actually
//  posted to `/api/coach`, since that's the wire contract this unit exists to
//  get right (no client-assembled `system`/`prompt` text, ever).

import Foundation
import Testing
@testable import GemmaChessCore

private let blunderFEN = "rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2"

/// Decodes just enough of the request body to assert on shape without
/// depending on `CoachOrchestrator`'s private `ChatFacts` type.
private struct CapturedCoachRequest: Decodable {
    let kind: String
    let facts: CapturedFacts
    let appUserId: String
    struct CapturedFacts: Decodable {
        let question: String?
        let fen: String?
        let openingName: String?
        let current: CoachLineInfo?
        let move: CoachLineInfo?
    }
}

@Suite("Coach: orchestrator", .serialized)
struct CoachOrchestratorTests {

    @Test("reports the managed coach's availability")
    func reportsAvailability() {
        let o = CoachOrchestrator(coach: .mockAnswering("hi"))
        #expect(o.availability == .managed)
    }

    @Test("an unconfigured managed coach -> unavailable + answering throws")
    func unconfiguredThrows() async {
        let coach = ManagedCoach(backendURL: { nil }, debugToken: { nil }, appUserId: { nil })
        let o = CoachOrchestrator(coach: coach)
        if case .unavailable = o.availability {} else { Issue.record("expected unavailable") }
        await #expect(throws: CoachError.self) {
            _ = try await o.answer(question: "best move?", fen: blunderFEN, depth: 12)
        }
    }

    @Test("answer() grounds the request in real engine facts, sent as structured JSON")
    func groundsAnswerInEngineFacts() async throws {
        var captured: CapturedCoachRequest?
        let o = CoachOrchestrator(coach: .mock { request in
            captured = try? JSONDecoder().decode(CapturedCoachRequest.self, from: request.httpBody ?? Data())
            return (200, Data(#"{"text":"g4 hangs the queen."}"#.utf8))
        })
        let reply = try await o.answer(
            question: "Why is g4 bad here?",
            fen: blunderFEN, lastMove: "g4", moveFen: blunderFEN, depth: 12
        )
        #expect(reply.answer == "g4 hangs the queen.")
        let req = try #require(captured)
        #expect(req.kind == "chat")
        #expect(req.facts.question == "Why is g4 bad here?")
        #expect(req.facts.fen == blunderFEN)
        // moveFen == fen -> the move is graded as part of the CURRENT-position
        // analysis (`current.move`), not a separate `move` block (see
        // `buildChatFacts`'s `moveAtCurrent` branch).
        #expect(req.facts.current?.move?.moveSan == "g4")
        #expect(req.facts.current?.move?.classification == "blunder")
    }

    @Test("pre-supplied currentFacts/moveFacts are forwarded unchanged, no engine call needed")
    func preSuppliedFactsPassThrough() async throws {
        var captured: CapturedCoachRequest?
        let o = CoachOrchestrator(coach: .mock { request in
            captured = try? JSONDecoder().decode(CapturedCoachRequest.self, from: request.httpBody ?? Data())
            return (200, Data(#"{"text":"ok"}"#.utf8))
        })
        let current = CoachLineInfo(bestSan: "Nf3", eval: "+0.30", winPercent: 55, lineSan: ["Nf3"])
        _ = try await o.answer(question: "what now?", currentFacts: current, depth: 12)

        let req = try #require(captured)
        #expect(req.facts.current?.bestSan == "Nf3")
        #expect(req.facts.current?.winPercent == 55)
    }

    @Test("the request body carries no system/prompt keys -- facts only")
    func noSystemOrPromptOnTheWire() async throws {
        var rawBody: [String: Any] = [:]
        let o = CoachOrchestrator(coach: .mock { request in
            if let data = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rawBody = json
            }
            return (200, Data(#"{"text":"ok"}"#.utf8))
        })
        _ = try await o.answer(question: "why?", fen: blunderFEN, depth: 12)

        #expect(rawBody["system"] == nil)
        #expect(rawBody["prompt"] == nil)
        #expect(rawBody["kind"] as? String == "chat")
        #expect(rawBody["facts"] != nil)
    }

    @Test("PlayViewModel's move-note path sends kind: moveNote, distinct from chat")
    func moveNoteKindIsDistinct() async throws {
        var capturedKind: String?
        let o = CoachOrchestrator(coach: .mock { request in
            let json = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            capturedKind = json?["kind"] as? String
            return (200, Data(#"{"text":"Solid."}"#.utf8))
        })
        _ = try await o.answer(question: "why?", lastMove: "e4", moveFen: blunderFEN, kind: .moveNote)
        #expect(capturedKind == "moveNote")
    }

    @Test("gameSummary() sends kind: summary with the imported-game facts, source: imported")
    func gameSummaryGrounding() async throws {
        var rawBody: [String: Any] = [:]
        let o = CoachOrchestrator(coach: .mock { request in
            if let data = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rawBody = json
            }
            return (200, Data(#"{"text":"Nice game."}"#.utf8))
        })
        let input = CoachGameInput(
            white: "alice", black: "bob", result: "1-0", opening: "Italian Game",
            speed: "blitz", player: .white, accuracyWhite: 92.7, accuracyBlack: 81.0,
            mistakes: [CoachFlaggedMove(moveNumber: 4, color: .white, moveSan: "Nf3",
                classification: "blunder", winBefore: 80.8, winAfter: 56.9, winSwing: 23.9,
                bestMoveSan: "c3", comment: "Allows a fork.")]
        )
        let summary = try await o.gameSummary(input, profileFacts: "You hang pieces in time trouble.")
        #expect(summary == "Nice game.")
        #expect(rawBody["kind"] as? String == "summary")
        let facts = rawBody["facts"] as? [String: Any]
        #expect(facts?["source"] as? String == "imported")
        #expect(facts?["white"] as? String == "alice")
        #expect((facts?["accuracyWhite"] as? Double) == 92.7)
    }

    @Test("summaryStream() sends kind: summary with the Play-game facts, source: play")
    func playSummaryGrounding() async throws {
        var rawBody: [String: Any] = [:]
        let o = CoachOrchestrator(coach: .mock { request in
            if let data = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rawBody = json
            }
            return (200, Data("data: {\"text\":\"Good fight.\"}\n\ndata: [DONE]\n\n".utf8))
        })
        let input = CoachPlayGameInput(
            result: "Checkmate — you win.", playerSide: .black, opening: "Sicilian Defense",
            records: [.init(moveNumber: 1, san: "c5", classification: "best", winBefore: 50, winAfter: 52,
                             betterSan: nil)]
        )
        var chunks: [String] = []
        for try await partial in try await o.summaryStream(input) { chunks.append(partial) }

        #expect(chunks == ["Good fight."])
        #expect(rawBody["kind"] as? String == "summary")
        let facts = rawBody["facts"] as? [String: Any]
        #expect(facts?["source"] as? String == "play")
        #expect(facts?["playerSide"] as? String == "black")
    }
}
