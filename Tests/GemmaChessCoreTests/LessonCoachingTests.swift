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
/// was actually reached. Wraps a real `ManagedCoach` over a mock URLProtocol
/// (see `TestSupport.swift`) since `CoachOrchestrator` now depends on
/// `ManagedCoach` concretely -- there's no more `CoachLLM` protocol to fake.
private final class CountingMockCoach: @unchecked Sendable {
    let replyText = "Look for the pin along the back rank."
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }

    lazy var orchestrator: CoachOrchestrator = CoachOrchestrator(coach: .mock { [weak self] _ in
        self?.lock.lock(); self?._callCount += 1; self?.lock.unlock()
        return (200, Data("{\"text\":\"\(self?.replyText ?? "")\"}".utf8))
    })
}

/// A `CoachOrchestrator` whose Pro-entitlement gate is forced to fail
/// (`.appStore` channel, `isProActive` false in a test binary) -- stands in
/// for a real gate failure without needing a real distribution channel.
private func proGatedOrchestrator() -> CoachOrchestrator {
    CoachOrchestrator(coach: .mockAnswering("unused"), channel: .appStore)
}

/// A `CoachOrchestrator` whose managed coach always fails with a generic
/// (non-Pro-gate) error -- stands in for a network/backend failure surfaced
/// as a `CoachError`.
private func failingOrchestrator() -> CoachOrchestrator {
    CoachOrchestrator(coach: .mockFailing(status: 500))
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
            coach: coach.orchestrator
        )
        vm.startSession(pack: pack)

        #expect(vm.coachAnswer == nil)
        await vm.askQuestion("Why is this the best move?")

        #expect(coach.callCount == 1)
        #expect(vm.coachAnswer == coach.replyText)
        #expect(vm.showPaywall == false)
        #expect(vm.coachError == nil)
    }

    @Test("askQuestion: a Pro-gate failure surfaces the paywall instead of a generic error")
    func gateFailureSurfacesPaywall() async {
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: proGatedOrchestrator()
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
            coach: coach.orchestrator
        )
        vm.startSession(pack: pack)

        await vm.askQuestion("   \n  ")

        #expect(coach.callCount == 0)
        #expect(vm.coachAnswer == nil)
        #expect(vm.showPaywall == false)
        #expect(vm.coachError == nil)
    }

    @Test("askQuestion: a generic CoachError populates coachError, distinct from the paywall path")
    func genericErrorPopulatesCoachError() async {
        let vm = LessonViewModel(
            lesson: lesson,
            progressDefaults: UserDefaults(suiteName: #function)!,
            coach: failingOrchestrator()
        )
        vm.startSession(pack: pack)

        await vm.askQuestion("Why is this the best move?")

        #expect(vm.coachError?.contains("Managed coach error (HTTP 500)") == true)
        #expect(vm.showPaywall == false)
        #expect(vm.coachAnswer == nil)
    }
}
