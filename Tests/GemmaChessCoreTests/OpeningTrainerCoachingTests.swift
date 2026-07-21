//  OpeningTrainerCoachingTests.swift
//  Covers the three opening-trainer additions: the free "Hint" reveal, the
//  Pro-gated coaching call (both the canned "why this move" question and a
//  free-form follow-up), and the explanation-cache seam -- a cache hit must
//  skip the coach backend entirely, and only the canned question is ever
//  cached (free-form questions are not).

import Testing
import Foundation
@testable import GemmaChessCore

/// Counts calls and returns a canned reply -- lets tests assert whether the
/// backend was actually reached (e.g. skipped on a cache hit). Wraps a real
/// `ManagedCoach` over a mock URLProtocol (see `TestSupport.swift`) since
/// `CoachOrchestrator` now depends on `ManagedCoach` concretely -- there's no
/// more `CoachLLM` protocol to fake.
private final class CountingMockCoach: @unchecked Sendable {
    let replyText = "Because it develops a piece and controls the center."
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

/// Records every read/write so tests can assert exactly what was cached (and
/// what wasn't -- free-form questions must never touch this).
private actor SpyOpeningExplanationCache: OpeningExplanationCache {
    private(set) var reads: [(lineID: String, moveIndex: Int)] = []
    private(set) var writes: [(explanation: String, lineID: String, moveIndex: Int)] = []
    private var seeded: [String: String] = [:]

    func seed(_ explanation: String, lineID: String, moveIndex: Int) {
        seeded["\(lineID)#\(moveIndex)"] = explanation
    }

    func cachedExplanation(lineID: String, moveIndex: Int) async -> String? {
        reads.append((lineID, moveIndex))
        return seeded["\(lineID)#\(moveIndex)"]
    }

    func store(explanation: String, lineID: String, moveIndex: Int) async {
        writes.append((explanation, lineID, moveIndex))
    }

    var readCount: Int { reads.count }
    var writeCount: Int { writes.count }
}

@MainActor
@Suite("OpeningTrainerViewModel: hint + Pro-gated coaching")
struct OpeningTrainerCoachingTests {

    // A short, real 2-move opening so `askWhyCurrentMove()` has a concrete
    // next move to ask about.
    private let line = Openings.OpeningLine(eco: "C50", name: "Italian Game", sanMoves: ["e4", "e5", "Nf3"])

    @Test("showHint reveals the line's next move without touching the coach")
    func hintRevealsNextMoveLocally() async {
        let coach = CountingMockCoach()
        let vm = OpeningTrainerViewModel(
            defaults: UserDefaults(suiteName: #function)!,
            coach: coach.orchestrator
        )
        vm.start(line: line, userIsWhite: true)

        #expect(vm.revealedHintSAN == nil)
        vm.showHint()
        #expect(vm.revealedHintSAN == "e4")   // White to move first; user plays White here
        #expect(coach.callCount == 0)   // purely local, no backend call
    }

    @Test("askWhyCurrentMove: a cache miss calls the coach and stores the result")
    func cacheMissCallsCoachAndStores() async {
        let coach = CountingMockCoach()
        let cache = SpyOpeningExplanationCache()
        let vm = OpeningTrainerViewModel(
            defaults: UserDefaults(suiteName: #function)!,
            coach: coach.orchestrator,
            explanationCache: cache
        )
        vm.start(line: line, userIsWhite: true)

        await vm.askWhyCurrentMove()

        #expect(coach.callCount == 1)
        #expect(vm.coachAnswer == coach.replyText)
        #expect(await cache.readCount == 1)
        #expect(await cache.writeCount == 1)
        let write = await cache.writes.first
        #expect(write?.lineID == line.id)
        #expect(write?.moveIndex == 0)
    }

    @Test("askWhyCurrentMove: a cache hit skips the coach backend entirely")
    func cacheHitSkipsCoachBackend() async {
        let coach = CountingMockCoach()
        let cache = SpyOpeningExplanationCache()
        await cache.seed("Cached: develops toward the center.", lineID: line.id, moveIndex: 0)
        let vm = OpeningTrainerViewModel(
            defaults: UserDefaults(suiteName: #function)!,
            coach: coach.orchestrator,
            explanationCache: cache
        )
        vm.start(line: line, userIsWhite: true)

        await vm.askWhyCurrentMove()

        #expect(coach.callCount == 0)   // never reached the backend
        #expect(vm.coachAnswer == "Cached: develops toward the center.")
        #expect(await cache.writeCount == 0)   // nothing new to store
    }

    @Test("askQuestion: a free-form question is never read from or written to the cache")
    func freeFormQuestionBypassesCache() async {
        let coach = CountingMockCoach()
        let cache = SpyOpeningExplanationCache()
        let vm = OpeningTrainerViewModel(
            defaults: UserDefaults(suiteName: #function)!,
            coach: coach.orchestrator,
            explanationCache: cache
        )
        vm.start(line: line, userIsWhite: true)

        await vm.askQuestion("What's the main alternative here?")

        #expect(coach.callCount == 1)
        #expect(vm.coachAnswer == coach.replyText)
        #expect(await cache.readCount == 0)
        #expect(await cache.writeCount == 0)
    }

    @Test("askWhyCurrentMove: a Pro-gate failure surfaces the paywall instead of a generic error")
    func gateFailureSurfacesPaywall() async {
        let vm = OpeningTrainerViewModel(
            defaults: UserDefaults(suiteName: #function)!,
            coach: proGatedOrchestrator()
        )
        vm.start(line: line, userIsWhite: true)

        #expect(vm.showPaywall == false)
        await vm.askWhyCurrentMove()

        #expect(vm.showPaywall)
        #expect(vm.coachAnswer == nil)
        #expect(vm.coachError == nil)
    }
}
