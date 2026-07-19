//  LessonCoachingTests.swift
//  Covers `LessonViewModel`'s Pro-gated free-form coaching call (U7): a
//  free-form question answers normally when entitled, surfaces the paywall
//  on a `ProRequiredError` instead of a generic error, is a no-op for an
//  empty/whitespace-only question, and populates `coachError` distinctly for
//  a generic `CoachError` -- mirroring `OpeningTrainerCoachingTests`'s
//  structure and mocking style, minus the caching seam (see this unit's
//  header/KTD-8: there's no canned per-position question here to cache).

import Testing
import Foundation
@testable import GemmaChessCore

/// Counts calls and returns a canned reply -- lets tests assert the backend
/// was actually reached.
private actor CountingMockCoach: CoachLLM {
    nonisolated var availability: CoachAvailability { .gemini }
    private(set) var callCount = 0
    nonisolated let replyText = "Look for the pin along the back rank."

    func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        callCount += 1
        return CoachReply(answer: replyText)
    }
}

/// Always throws `ProRequiredError` -- stands in for a failed entitlement gate.
private final class ProGatedMockCoach: CoachLLM {
    var availability: CoachAvailability { .gemini }
    func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        throw ProRequiredError()
    }
}

/// Always throws a generic `CoachError` -- stands in for a non-Pro-gated
/// backend failure (e.g. a network error surfaced as a `CoachError`).
private final class FailingMockCoach: CoachLLM {
    var availability: CoachAvailability { .gemini }
    func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        throw CoachError("The coach is temporarily unavailable.")
    }
}

@MainActor
@Suite("LessonViewModel: Pro-gated coach Q&A")
struct LessonCoachingTests {

    private let lesson = Lesson(
        id: "test-lesson", title: "Test Lesson", theme: "fork",
        bodyText: "Body text.", puzzleCount: 2
    )

    private let pack = PuzzlePack(theme: "fork", puzzles: [
        Puzzle(
            id: "p1", fen: "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            moves: ["f3g5", "d7d5", "e4d5", "g8f6"], rating: 900, themes: ["fork"]
        ),
    ])

    @Test("askQuestion: an entitled backend answers and populates coachAnswer")
    func entitledQuestionPopulatesAnswer() async {
        let coach = CountingMockCoach()
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: CoachOrchestrator(backends: [coach])
        )
        vm.startSession(pack: pack)

        #expect(vm.coachAnswer == nil)
        await vm.askQuestion("Why is this the best move?")

        #expect(await coach.callCount == 1)
        #expect(vm.coachAnswer == coach.replyText)
        #expect(vm.showPaywall == false)
        #expect(vm.coachError == nil)
    }

    @Test("askQuestion: a Pro-gate failure surfaces the paywall instead of a generic error")
    func gateFailureSurfacesPaywall() async {
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: CoachOrchestrator(backends: [ProGatedMockCoach()])
        )
        vm.startSession(pack: pack)

        #expect(vm.showPaywall == false)
        await vm.askQuestion("Why is this the best move?")

        #expect(vm.showPaywall)
        #expect(vm.coachAnswer == nil)
        #expect(vm.coachError == nil)
    }

    @Test("askQuestion: an empty/whitespace-only question is a no-op")
    func emptyQuestionIsNoOp() async {
        let coach = CountingMockCoach()
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: CoachOrchestrator(backends: [coach])
        )
        vm.startSession(pack: pack)

        await vm.askQuestion("   \n  ")

        #expect(await coach.callCount == 0)
        #expect(vm.coachAnswer == nil)
        #expect(vm.showPaywall == false)
        #expect(vm.coachError == nil)
    }

    @Test("askQuestion: a generic CoachError populates coachError, distinct from the paywall path")
    func genericErrorPopulatesCoachError() async {
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: CoachOrchestrator(backends: [FailingMockCoach()])
        )
        vm.startSession(pack: pack)

        await vm.askQuestion("Why is this the best move?")

        #expect(vm.coachError == "The coach is temporarily unavailable.")
        #expect(vm.showPaywall == false)
        #expect(vm.coachAnswer == nil)
    }
}
