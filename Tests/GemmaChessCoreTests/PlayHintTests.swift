//  PlayHintTests.swift
//  Hint mode (the bulb, plan 2026-07-21-003 U2): `requestHint` runs a multipv-2
//  analysis and populates the best move, a distinct legal alternative, and a
//  template-based rationale — engine-only, identical on both tiers, no network
//  (covers origin AE3). The bulb is a persistent MODE: while on, the hint
//  auto-refreshes after every engine reply; turning it off (or starting a new
//  game) clears it and stops the auto-refresh. Uses real Stockfish, so shallow
//  depth and serialized.

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

    /// Whether a UCI string names a legal move in `fen`.
    private func isLegal(_ uci: String, in fen: String = PlayHintTests.start) -> Bool {
        ChessLogic.fen(afterMove: uci, fromFEN: fen) != nil
    }

    @Test func requestHintPopulatesBestAndDistinctSecond() async {
        let vm = PlayViewModel.forTesting()
        #expect(vm.hint == nil)

        vm.requestHint()
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

    @Test func clearHintEmptiesItAndTurnsModeOff() async {
        let vm = PlayViewModel.forTesting()
        vm.toggleHintMode()
        #expect(vm.hintMode)
        await wait { vm.hint?.bestUCI.isEmpty == false }
        #expect(vm.hint != nil)
        vm.clearHint()
        #expect(vm.hint == nil)
        #expect(vm.hintMode == false)
    }

    /// With hint mode OFF, a directly requested hint is still cleared by a new
    /// move — a one-shot hint never lingers against a changed position.
    @Test func newMoveClearsHintWhenModeOff() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.requestHint()
        await wait { vm.hint?.bestUCI.isEmpty == false }
        #expect(vm.hint != nil)
        #expect(vm.hintMode == false)

        // Play 1.e4 — with the mode off, the move clears the showing hint.
        vm.tap(.e2)
        vm.tap(.e4)
        #expect(vm.hint == nil)
    }

    /// AE3 — the hint is engine-only on every tier: the template rationale is
    /// populated with the coach disabled, with no network dependency, and the
    /// resulting `HintInfo` has the same shape regardless of coach state
    /// (there is no Pro rationale field at all any more).
    @Test func hintIsEngineOnlyRegardlessOfCoachState() async {
        let coachOff = PlayViewModel.forTesting()
        coachOff.coachDisplayEnabled = false
        let coachOn = PlayViewModel.forTesting()
        coachOn.coachDisplayEnabled = true

        coachOff.requestHint()
        coachOn.requestHint()
        await wait { coachOff.hint?.bestUCI.isEmpty == false && coachOn.hint?.bestUCI.isEmpty == false }

        #expect(coachOff.hint?.rationale?.isEmpty == false)
        #expect(coachOn.hint?.rationale?.isEmpty == false)
        // Same position, same engine, no coach involvement → identical hints.
        #expect(coachOff.hint == coachOn.hint)
        // The hint never touches the coach backend, so no coach error surfaces.
        #expect(coachOff.lastCoachError == nil)
        #expect(coachOn.lastCoachError == nil)
    }

    /// Mode persistence: with the bulb on, playing a move and getting the
    /// engine's reply produces a fresh hint for the new position — no second
    /// bulb tap needed.
    @Test func hintModeRefreshesAfterEngineReply() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.toggleHintMode()
        #expect(vm.hintMode)
        await wait { vm.hint?.bestUCI.isEmpty == false }
        let firstHint = vm.hint
        #expect(firstHint != nil)

        let countBefore = vm.hintRequestCount
        vm.tap(.e2)
        vm.tap(.e4)
        // Wait for the engine's reply AND the auto-refreshed hint to land for
        // the NEW position (the old hint deliberately stays visible meanwhile).
        await wait(upTo: 30) {
            vm.moves.count >= 2 && vm.userToMove && vm.hint?.forFEN == vm.fen
        }
        #expect(vm.hintMode)
        #expect(vm.hintRequestCount > countBefore)   // a fresh request fired without another bulb tap
        #expect(vm.hint?.forFEN == vm.fen)           // ...and its result is for the current position
        #expect(vm.hint?.bestUCI.isEmpty == false)
        #expect(isLegal(vm.hint?.bestUCI ?? "", in: vm.fen))
    }

    /// Mode off: after turning the bulb off, no re-request fires on the next turn.
    @Test func hintModeOffStopsAutoRequests() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.toggleHintMode()
        await wait { vm.hint?.bestUCI.isEmpty == false }
        vm.toggleHintMode()   // bulb off
        #expect(vm.hintMode == false)
        #expect(vm.hint == nil)

        vm.tap(.e2)
        vm.tap(.e4)
        await wait(upTo: 30) { vm.moves.count >= 2 && vm.userToMove }
        // Give any (wrong) auto-request time to land, then confirm none did.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(vm.hint == nil)
        #expect(vm.hintMode == false)
    }

    /// New game: the bulb resets to off even if it was on before.
    @Test func newGameResetsHintMode() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.toggleHintMode()
        #expect(vm.hintMode)
        vm.newGame(asWhite: true)
        #expect(vm.hintMode == false)
        #expect(vm.hint == nil)
    }

    /// Edge: while browsing history, `requestHint` is a no-op — no hint appears
    /// for a live position while a historical one is on the board.
    @Test func noHintWhileViewingHistory() async {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.tap(.e2)
        vm.tap(.e4)
        await wait(upTo: 30) { vm.moves.count >= 2 && vm.userToMove }

        vm.viewTo(ply: 0)
        #expect(vm.isViewingHistory)
        vm.requestHint()
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(vm.hint == nil)
    }

    @Test func hintSummaryLabelFormatsBestAndAlt() {
        let both = HintInfo(bestUCI: "g1f3", secondUCI: "e2e4",
                            bestSAN: "Nf3", secondSAN: "e4",
                            rationale: nil)
        #expect(both.summaryLabel == "Best: Nf3 · Alt: e4")

        let bestOnly = HintInfo(bestUCI: "g1f3", secondUCI: nil,
                                bestSAN: "Nf3", secondSAN: nil,
                                rationale: nil)
        #expect(bestOnly.summaryLabel == "Best: Nf3")
    }
}
