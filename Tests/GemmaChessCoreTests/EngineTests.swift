//  EngineTests.swift
//  Covers U5 (EnginePool) and U6 (EngineLine). These spin up real Stockfish, so
//  they run at a shallow depth, serialized, and share ONE engine instance — which
//  also mirrors production usage (a single EnginePool.shared), avoiding many
//  concurrent Stockfish starts.

import Testing
@testable import GemmaChessCore

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

@Suite("Engine", .serialized)
struct EngineSuite {

    // U5 — EnginePool

    @Test("analyses the start position: a sane best move and near-even eval")
    func startPosition() async throws {
        let r = try await EnginePool.shared.analyse(fen: startFEN, depth: 12, multipv: 1)
        #expect(r.lines.count == 1)
        #expect(!r.best.pvUCI.isEmpty)
        #expect(abs(r.best.signedCp) < 200)
        #expect(r.best.winPercent > 40 && r.best.winPercent < 65)
    }

    @Test("multipv returns the requested number of ordered lines")
    func multipv() async throws {
        let r = try await EnginePool.shared.analyse(fen: startFEN, depth: 12, multipv: 3)
        #expect(r.lines.count == 3)
        // Tolerance covers multipv score jitter between lines reported at slightly
        // different search moments (observed ~0.1 win% under parallel test load).
        #expect(r.lines[0].winPercent >= r.lines[1].winPercent - 0.25)
    }

    @Test("identical query is served from cache (equal result)")
    func caching() async throws {
        let a = try await EnginePool.shared.analyse(fen: startFEN, depth: 12, multipv: 1)
        let b = try await EnginePool.shared.analyse(fen: startFEN, depth: 12, multipv: 1)
        #expect(a == b)
    }

    @Test("a strong winning position evaluates well above 50% for the side to move")
    func winningPosition() async throws {
        // White up a rook in a simple position.
        let r = try await EnginePool.shared.analyse(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", depth: 14, multipv: 1)
        #expect(r.best.winPercent > 55)
    }

    // U6 — EngineLine

    @Test("eval string formatting")
    func evalStrings() {
        #expect(EngineLine.evalStr(cp: 234, mate: nil) == "+2.34")
        #expect(EngineLine.evalStr(cp: -50, mate: nil) == "-0.50")
        #expect(EngineLine.evalStr(cp: nil, mate: 3) == "#3")
        #expect(EngineLine.evalStr(cp: nil, mate: -2) == "#-2")
        #expect(EngineLine.evalStrFromSignedCp(GCConfig.mateScoreCp) == "#")
        #expect(EngineLine.evalStrFromSignedCp(-GCConfig.mateScoreCp) == "#-")
        #expect(EngineLine.evalStrFromSignedCp(120) == "+1.20")
    }

    @Test("best line for the start position; side to move is white")
    func bestLine() async throws {
        let r = try await EngineLine.evaluate(fen: startFEN, depth: 12, multipv: 1, engine: EnginePool.shared)
        #expect(r.sideToMove == "white")
        #expect(r.bestSAN != nil)
        #expect(!r.lineSAN.isEmpty)
        #expect(r.move == nil)
    }

    @Test("a losing move is flagged a blunder with a refutation")
    func blunderMove() async throws {
        // After 1.f3 e5, White to move. 2.g4?? allows 2...Qh4#.
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2"
        let r = try await EngineLine.evaluate(fen: fen, move: "g4", depth: 14, multipv: 1, engine: EnginePool.shared)
        let m = try #require(r.move)
        #expect(m.moveSAN == "g4")
        #expect(m.classification == "blunder")
        #expect(m.winAfter < m.winBefore)
        #expect(!m.refutationLineSAN.isEmpty)
    }

    @Test("coachInfo conversion carries the move verdict to the coach facts")
    func coachInfoBridge() async throws {
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2"
        let r = try await EngineLine.evaluate(fen: fen, move: "g4", depth: 14, multipv: 1, engine: EnginePool.shared)
        let text = try #require(CoachPromptBuilder.engineFactsText(r.coachInfo))
        #expect(text.contains("The move g4 is classified a blunder"))
    }
}
