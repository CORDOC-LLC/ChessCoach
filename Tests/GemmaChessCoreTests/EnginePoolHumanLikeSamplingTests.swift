//  EnginePoolHumanLikeSamplingTests.swift
//  U2 — the Human-like opponent's weighted MultiPV move sampling: at low skill,
//  `EnginePool.humanLikeMove` always returns a real top-N candidate (never an
//  arbitrary/illegal move), sometimes a non-best one, degrades gracefully with
//  very few legal moves, and the `PlayViewModel` threshold predicate that gates
//  it is exactly right at the boundary. Uses real Stockfish (shallow depth), so
//  it's serialized like the other engine/game-loop tests.

import Testing
@testable import GemmaChessCore

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

@Suite("EnginePool: human-like weighted sampling", .serialized)
struct EnginePoolHumanLikeSamplingTests {

    // MARK: EnginePool.humanLikeMove — happy path

    @Test("at low skill, sampled moves are always among the engine's own top-N candidates")
    func sampledMovesAreAlwaysTopNCandidates() async throws {
        let ground = try await EnginePool.shared.analyse(fen: startFEN, depth: 10, multipv: EnginePool.humanLikeMultiPV)
        let candidates = Set(ground.lines.compactMap { $0.pvUCI.first })
        #expect(!candidates.isEmpty)

        for _ in 0..<20 {
            let move = try await EnginePool.shared.humanLikeMove(fen: startFEN, depth: 10, skill: 0)
            let picked = try #require(move)
            #expect(candidates.contains(picked))
        }
    }

    @Test("at low skill, repeated sampling occasionally picks a non-top candidate")
    func samplingOccasionallyPicksANonTopCandidate() async throws {
        // The start position has several genuinely playable first moves (e4, d4,
        // Nf3, c4, ...) whose shallow-depth evals are close enough for skill-0's
        // flat weighting to give real variety -- this proves sampling isn't
        // secretly always returning index 0.
        let ground = try await EnginePool.shared.analyse(fen: startFEN, depth: 10, multipv: EnginePool.humanLikeMultiPV)
        let best = try #require(ground.lines.first?.pvUCI.first)

        var sawNonBest = false
        for _ in 0..<30 {
            let move = try await EnginePool.shared.humanLikeMove(fen: startFEN, depth: 10, skill: 0)
            if let move, move != best {
                sawNonBest = true
                break
            }
        }
        #expect(sawNonBest)
    }

    // MARK: weightedPick — edge cases (pure, no engine)

    @Test("weightedPick never crashes and stays within bounds for a single candidate")
    func weightedPickSingleCandidate() {
        let lines = [EngineLineResult(cp: 20, mate: nil, pvUCI: ["e2e4"])]
        for skill in 0...9 {
            #expect(EnginePool.weightedPick(from: lines, skill: skill) == "e2e4")
        }
    }

    @Test("weightedPick handles zero candidates without crashing")
    func weightedPickZeroCandidates() {
        #expect(EnginePool.weightedPick(from: [], skill: 0) == nil)
    }

    @Test("weightedPick handles lines with an empty PV without crashing")
    func weightedPickEmptyPV() {
        let lines = [
            EngineLineResult(cp: 20, mate: nil, pvUCI: []),
            EngineLineResult(cp: 10, mate: nil, pvUCI: ["d2d4"]),
        ]
        let move = EnginePool.weightedPick(from: lines, skill: 3)
        #expect(move == "d2d4")
    }

    @Test("weightedPick degrades gracefully when fewer candidates than the usual N exist")
    func weightedPickFewCandidates() {
        let lines = [
            EngineLineResult(cp: 5, mate: nil, pvUCI: ["g1f3"]),
            EngineLineResult(cp: -10, mate: nil, pvUCI: ["b1c3"]),
        ]
        for skill in 0..<EnginePool.lowSkillThreshold {
            let move = EnginePool.weightedPick(from: lines, skill: skill)
            #expect(move == "g1f3" || move == "b1c3")
        }
    }

    @Test("humanLikeMove doesn't crash on a near-mate position with very few legal moves")
    func humanLikeMoveFewLegalMoves() async throws {
        // Black king on h8 boxed in by its own pawns/pieces with one escape --
        // few legal replies overall for White to consider isn't the point here;
        // instead exercise a position where MultiPV naturally returns fewer than
        // the requested count of lines (near-forced sequences).
        let fen = "6k1/6pp/8/8/8/8/6PP/6K1 w - - 0 1"
        let move = try await EnginePool.shared.humanLikeMove(fen: fen, depth: 8, skill: 2, multipv: EnginePool.humanLikeMultiPV)
        #expect(move != nil)
    }

    // MARK: PlayViewModel threshold predicate — boundary + toggle-off regression

    @MainActor
    @Test("threshold predicate: below threshold with toggle on is true, at/above is false")
    func thresholdPredicateBoundary() {
        let vm = PlayViewModel.forTesting()
        vm.humanLikeEnabled = true

        vm.skill = EnginePool.lowSkillThreshold - 1
        #expect(vm.usesHumanLikeSampling)

        vm.skill = EnginePool.lowSkillThreshold
        #expect(!vm.usesHumanLikeSampling)

        vm.skill = EnginePool.lowSkillThreshold + 5
        #expect(!vm.usesHumanLikeSampling)
    }

    @MainActor
    @Test("toggle-off regression: the predicate is false at any skill when the toggle is off")
    func toggleOffRegression() {
        let vm = PlayViewModel.forTesting()
        vm.humanLikeEnabled = false

        for skill in [0, 1, 5, EnginePool.lowSkillThreshold - 1, EnginePool.lowSkillThreshold, 20] {
            vm.skill = skill
            #expect(!vm.usesHumanLikeSampling)
        }
    }
}
