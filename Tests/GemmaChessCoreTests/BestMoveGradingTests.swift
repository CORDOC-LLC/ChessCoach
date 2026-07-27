//  BestMoveGradingTests.swift
//  Pins the reported bug: a move that was NOT the engine's top choice was
//  graded "Best" and captioned "The engine's top choice", while the same chip
//  displayed "best Re1" beside it.
//
//  Reported position: White down ~6.5 pawns, played Kb1, engine wanted Re1.
//  Win% is saturated that far behind, so a half-pawn giveaway cost under the
//  2.0 win% allowance and slipped through as "best".

import Testing
@testable import GemmaChessCore

@Suite("Best-move grading honesty")
struct BestMoveGradingTests {

    /// Win% at the evals from the report, so the tests below use real numbers
    /// rather than invented ones.
    private func win(_ pawns: Double) -> Double { Evaluation.winPercent(pawns * 100) }

    @Test("win% really is saturated at a lopsided eval -- the root cause")
    func winPercentSaturates() {
        // Losing a further half pawn from -6.50 costs well under `bestEps`,
        // which is why the win%-only rule let it through.
        let drop = win(-6.50) - win(-7.00)
        #expect(drop < Evaluation.bestEps)
    }

    @Test("the reported case: half a pawn given up in a lost position is not best")
    func lostPositionHalfPawnIsNotBest() {
        let cls = Evaluation.classify(
            winBefore: win(-6.50), winAfter: win(-7.00),
            isBest: false, cpLoss: 50.0 + 1)
        #expect(cls != .best)
        #expect(cls == .good)
    }

    @Test("a genuinely equivalent move still grades best")
    func equivalentMoveStillBest() {
        // Same tiny win% drop, but only a few centipawns given up.
        let cls = Evaluation.classify(
            winBefore: win(-6.50), winAfter: win(-6.55),
            isBest: false, cpLoss: 5)
        #expect(cls == .best)
    }

    @Test("the engine's own top choice is always best, whatever the centipawns say")
    func engineTopChoiceAlwaysBest() {
        let cls = Evaluation.classify(
            winBefore: win(-6.50), winAfter: win(-9.00),
            isBest: true, cpLoss: 250)
        #expect(cls == .best)
    }

    @Test("omitting cpLoss preserves the previous behaviour for callers without it")
    func cpLossIsOptional() {
        let cls = Evaluation.classify(winBefore: win(-6.50), winAfter: win(-7.00))
        #expect(cls == .best)
    }

    @Test("a big centipawn loss is still graded by win% when the drop is large")
    func largeWinDropStillOutranksTheGuard() {
        // Near equality, throwing away a rook is a blunder on win% alone; the
        // cp guard must not interfere with the normal thresholds.
        let cls = Evaluation.classify(
            winBefore: win(0.2), winAfter: win(-5.0), isBest: false, cpLoss: 520)
        #expect(cls == .blunder)
    }

    // MARK: Chip label

    @Test("chip says Solid, not Best, when the engine picked something else")
    func chipLabelForNearEquivalent() {
        let v = MoveVerdict(moveSAN: "Kb1", classification: "best",
                            isBest: false, betterMoveSAN: "Re1")
        #expect(v.displayLabel == "Solid")
    }

    @Test("chip still says Best when the move WAS the engine's choice")
    func chipLabelForTrueBest() {
        let v = MoveVerdict(moveSAN: "Ng5", classification: "best",
                            isBest: true, betterMoveSAN: nil)
        #expect(v.displayLabel == "Best")
    }

    @Test("other classifications are unaffected by the label rule")
    func otherLabelsUnchanged() {
        for cls in ["good", "inaccuracy", "mistake", "blunder"] {
            let v = MoveVerdict(moveSAN: "a3", classification: cls,
                                isBest: false, betterMoveSAN: "Re1")
            #expect(v.displayLabel == cls.capitalized)
        }
    }

    // MARK: Comment copy

    @Test("the comment stops claiming 'top choice' when it wasn't")
    func commentDoesNotClaimTopChoice() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let after = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: fen, fenAfter: after, moveUCI: "e2e4", moveSAN: "e4",
            classification: "best", betterMoveSAN: "Re1", evalAfter: "-6.5")
        #expect(!text.contains("top choice"))
        #expect(text.contains("Re1"))
    }

    @Test("the comment still credits a genuine top choice")
    func commentCreditsTrueTopChoice() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let after = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: fen, fenAfter: after, moveUCI: "e2e4", moveSAN: "e4",
            classification: "best", betterMoveSAN: nil, evalAfter: "+0.3")
        #expect(text.contains("top choice"))
    }
}
