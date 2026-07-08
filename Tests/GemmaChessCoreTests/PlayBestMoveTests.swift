//  PlayBestMoveTests.swift
//  U5 — best-move hint caching: the VM analyses a position once, caches the result
//  per FEN, and a repeat request does not trigger a second analysis. Uses real
//  Stockfish, so shallow depth and serialized.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("PlayBestMove", .serialized)
@MainActor
struct PlayBestMoveTests {

    static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// Poll until `condition` holds or we give up (the analysis runs on a Task).
    private func wait(upTo seconds: Double = 12, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test func cachesBestMoveAndAvoidsReanalysis() async {
        let vm = PlayViewModel.forTesting()
        #expect(vm.bestMove(forFEN: Self.start) == nil)   // nothing cached yet

        vm.requestBestMove(forFEN: Self.start)
        await wait { vm.bestMove(forFEN: Self.start) != nil }

        let best = vm.bestMove(forFEN: Self.start)
        #expect(best != nil)
        #expect((best?.count ?? 0) >= 4)               // a UCI move
        #expect(vm.bestMoveAnalysisCount == 1)

        // A repeat request for the same FEN is a cache hit — no second analysis.
        vm.requestBestMove(forFEN: Self.start)
        #expect(vm.bestMoveAnalysisCount == 1)
    }

    @Test func doesNotAnalyseTerminalPositions() async {
        let vm = PlayViewModel.forTesting()
        // Fool's mate — checkmate, no legal move to suggest.
        let mated = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
        vm.requestBestMove(forFEN: mated)
        #expect(vm.bestMoveAnalysisCount == 0)
        #expect(vm.bestMove(forFEN: mated) == nil)
    }
}
