//  PlayHintTests.swift
//  On-demand hint: `requestHint` runs a multipv-2 analysis and populates the best
//  move plus a distinct legal alternative; `clearHint` empties it; and a new move
//  clears a showing hint. Uses real Stockfish, so shallow depth and serialized.
//  (The coach rationale needs an on-device LLM, so it isn't asserted here.)

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@Suite("PlayHint", .serialized)
@MainActor
struct PlayHintTests {

    static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// Poll until `condition` holds or we give up (analysis runs on a Task).
    private func wait(upTo seconds: Double = 15, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Whether a UCI string names a legal move in the start position.
    private func isLegal(_ uci: String) -> Bool {
        ChessLogic.fen(afterMove: uci, fromFEN: Self.start) != nil
    }

    @Test func requestHintPopulatesBestAndDistinctSecond() async {
        let vm = PlayViewModel.forTesting()
        #expect(vm.hint == nil)

        vm.requestHint()
        // The hint object appears immediately (loading), then fills with the analysis.
        await wait { vm.hint?.bestUCI.isEmpty == false }

        let hint = vm.hint
        #expect(hint != nil)
        #expect((hint?.bestUCI.count ?? 0) >= 4)
        #expect(isLegal(hint?.bestUCI ?? ""))
        // multipv 2 → a distinct, legal alternative.
        let second = hint?.secondUCI
        #expect(second != nil)
        #expect(second != hint?.bestUCI)
        #expect(isLegal(second ?? ""))
        #expect(hint?.bestSAN.isEmpty == false)
    }

    @Test func clearHintEmptiesIt() async {
        let vm = PlayViewModel.forTesting()
        vm.requestHint()
        await wait { vm.hint?.bestUCI.isEmpty == false }
        #expect(vm.hint != nil)
        vm.clearHint()
        #expect(vm.hint == nil)
    }

    @Test func newMoveClearsExistingHint() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.requestHint()
        await wait { vm.hint?.bestUCI.isEmpty == false }
        #expect(vm.hint != nil)

        // Play 1.e4 — making a move must clear the showing hint.
        vm.tap(.e2)
        vm.tap(.e4)
        #expect(vm.hint == nil)
    }

    /// U3 — the free, template-based "why" is populated synchronously, in the same
    /// tick as the arrows/SAN, regardless of Pro coach status (no LLM/network wait).
    @Test func requestHintPopulatesFreeRationaleWithCoachDisabled() async {
        let vm = PlayViewModel.forTesting()
        vm.coachDisplayEnabled = false
        #expect(vm.hint == nil)

        vm.requestHint()
        await wait { vm.hint?.bestUCI.isEmpty == false }

        let hint = vm.hint
        #expect(hint != nil)
        #expect(hint?.freeRationale?.isEmpty == false)
        // Coach is off, so the Pro rationale never fills in -- distinct fields.
        #expect(hint?.rationale == nil)
        #expect(hint?.isLoading == false)
    }

    @Test func hintSummaryLabelFormatsBestAndAlt() {
        let both = HintInfo(bestUCI: "g1f3", secondUCI: "e2e4",
                            bestSAN: "Nf3", secondSAN: "e4",
                            rationale: nil, isLoading: false)
        #expect(both.summaryLabel == "Best: Nf3 · Alt: e4")

        let bestOnly = HintInfo(bestUCI: "g1f3", secondUCI: nil,
                                bestSAN: "Nf3", secondSAN: nil,
                                rationale: nil, isLoading: false)
        #expect(bestOnly.summaryLabel == "Best: Nf3")
    }
}
