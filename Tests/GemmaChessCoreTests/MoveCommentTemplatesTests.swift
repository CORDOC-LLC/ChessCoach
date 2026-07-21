//  MoveCommentTemplatesTests.swift
//  U3 — the free, template-based one-line comment about the move just played. Pure,
//  engine-free classification over the before/after FENs + the engine's already-known
//  verdict, so these tests never touch Stockfish: every FEN below is hand-constructed
//  to exercise one branch of the priority order.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@Suite("MoveCommentTemplates")
struct MoveCommentTemplatesTests {

    /// A quiet opening move (1. e4) — parses fine, no capture, nothing hangs.
    private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private static let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPPPPPP/RNBQKBNR b KQkq e3 0 1"

    private func quiet(
        classification: String, betterMoveSAN: String? = nil, evalAfter: String? = nil
    ) -> String {
        MoveCommentTemplates.comment(
            fenBefore: Self.startFEN, fenAfter: Self.afterE4,
            moveUCI: "e2e4", moveSAN: "e4",
            classification: classification, betterMoveSAN: betterMoveSAN, evalAfter: evalAfter)
    }

    // MARK: Affirmation and classification

    @Test func bestMoveGetsAnAffirmingLine() {
        let text = quiet(classification: "best")
        #expect(text == "The engine's top choice — well played.")
    }

    @Test func goodMoveGetsASolidLine() {
        #expect(quiet(classification: "good") == "A good, solid move.")
    }

    @Test func blunderNamesTheBetterMove() {
        let text = quiet(classification: "blunder", betterMoveSAN: "Nf3")
        #expect(text == "A blunder — Nf3 kept the pressure.")
    }

    @Test func blunderWithoutBetterMoveStillReadsAsABlunder() {
        let text = quiet(classification: "blunder")
        #expect(text.lowercased().contains("blunder"))
        #expect(!text.isEmpty)
    }

    @Test func mistakeAndInaccuracyNameTheBetterMove() {
        #expect(quiet(classification: "mistake", betterMoveSAN: "Nf3").contains("Nf3"))
        #expect(quiet(classification: "inaccuracy", betterMoveSAN: "Nf3").contains("Nf3"))
    }

    @Test func classificationIsCaseInsensitive() {
        #expect(quiet(classification: "Blunder", betterMoveSAN: "Nf3").contains("Nf3"))
        #expect(quiet(classification: "BEST") == "The engine's top choice — well played.")
    }

    // MARK: Mate delivered / forced mate (evalAfter sign convention)

    @Test func checkmateOnTheBoardBeatsEverything() {
        // Scholar's mate: 4. Qxf7#.
        let before = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
        let after = "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: after, moveUCI: "h5f7", moveSAN: "Qxf7#",
            classification: "best", betterMoveSAN: nil, evalAfter: nil)
        #expect(text == "Checkmate — game over.")
    }

    /// Pins the codebase sign convention: `EngineLineReport.MoveReport.evalAfter`
    /// is flipped BACK to the mover's perspective (`afterEvalCp = -after.signedCp`
    /// in EngineLine.swift), so "#2" means the player who just moved has the
    /// forced mate — NOT the side to move in `fenAfter`.
    @Test func positiveMateEvalMeansTheMoverHasForcedMate() {
        let text = quiet(classification: "best", evalAfter: "#2")
        #expect(text == "You now have a forced mate in 2 — finish it.")
    }

    @Test func mateInOneEvalPointsAtTheFinish() {
        let text = quiet(classification: "best", evalAfter: "#1")
        #expect(text == "Checkmate is one move away — go find it.")
    }

    @Test func negativeMateEvalMeansTheMoveAllowedMate() {
        let text = quiet(classification: "blunder", betterMoveSAN: "Nf3", evalAfter: "#-2")
        #expect(text == "This lets your opponent force checkmate — Nf3 held on.")
    }

    @Test func distanceLessMateStringsFromEvalStrFromSignedCpAreAccepted() {
        // `EngineLine.evalStrFromSignedCp` emits bare "#" / "#-".
        #expect(quiet(classification: "best", evalAfter: "#").lowercased().contains("checkmate"))
        let against = quiet(classification: "blunder", evalAfter: "#-")
        #expect(against.lowercased().contains("opponent"))
    }

    @Test func nonMateEvalStringsDoNotTriggerMatePhrasing() {
        #expect(quiet(classification: "best", evalAfter: "+0.35")
            == "The engine's top choice — well played.")
        #expect(quiet(classification: "best", evalAfter: "#garbage")
            == "The engine's top choice — well played.")
    }

    // MARK: Material lost / won

    @Test func hangingTheMovedPieceMentionsTheLoss() {
        // White knight b3 -> d4, where the black e5-pawn wins it (no defender).
        let before = "4k3/8/8/4p3/8/1N6/8/4K3 w - - 0 1"
        let after = "4k3/8/8/4p3/3N4/8/8/4K3 b - - 1 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: after, moveUCI: "b3d4", moveSAN: "Nd4",
            classification: "blunder", betterMoveSAN: "Nc5", evalAfter: nil)
        #expect(text.contains("knight"))
        #expect(text.lowercased().contains("hanging"))
        #expect(text.contains("Nc5"))
    }

    @Test func captureWinningMaterialMentionsTheGain() {
        // White queen d1 takes an undefended black rook on d5.
        let before = "4k3/8/8/3r4/8/8/8/3QK3 w - - 0 1"
        let after = "4k3/8/8/3Q4/8/8/8/4K3 b - - 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: after, moveUCI: "d1d5", moveSAN: "Qxd5",
            classification: "best", betterMoveSAN: nil, evalAfter: nil)
        #expect(text.contains("rook"))
        #expect(text.lowercased().contains("wins"))
    }

    @Test func aBlunderThatCapturesIsNotPraisedForTheCapture() {
        // Queen grabs a defended pawn: capture is real, but the verdict says blunder —
        // the comment must not congratulate the material grab.
        let before = "4k3/4p3/3p4/8/8/8/8/3QK3 w - - 0 1"
        let after = "4k3/4p3/3Q4/8/8/8/8/4K3 b - - 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: after, moveUCI: "d1d6", moveSAN: "Qxd6",
            classification: "blunder", betterMoveSAN: "Qd4", evalAfter: nil)
        #expect(!text.lowercased().contains("wins"))
        #expect(text.lowercased().contains("hanging") || text.lowercased().contains("blunder"))
    }

    @Test func enPassantCaptureCountsAsWinningAPawn() {
        // White pawn d5 takes e6 en passant (black just played e7-e5).
        let before = "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"
        let after = "4k3/8/4P3/8/8/8/8/4K3 b - - 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: after, moveUCI: "d5e6", moveSAN: "dxe6",
            classification: "good", betterMoveSAN: nil, evalAfter: nil)
        #expect(text.contains("pawn"))
    }

    // MARK: Fail-soft on malformed input

    @Test func malformedInputsFallBackAndNeverCrash() {
        let bad = [
            MoveCommentTemplates.comment(
                fenBefore: "not a fen", fenAfter: "also bad", moveUCI: "e2e4", moveSAN: "e4",
                classification: "best", betterMoveSAN: nil, evalAfter: nil),
            MoveCommentTemplates.comment(
                fenBefore: Self.startFEN, fenAfter: Self.afterE4, moveUCI: "", moveSAN: "",
                classification: "", betterMoveSAN: nil, evalAfter: nil),
            MoveCommentTemplates.comment(
                fenBefore: "", fenAfter: "", moveUCI: "zz99", moveSAN: "",
                classification: "??", betterMoveSAN: nil, evalAfter: "???"),
        ]
        for text in bad {
            #expect(text == "A reasonable move — keep building your position.")
        }
    }

    @Test func badAfterFENIsRederivedFromTheMove() {
        // fenAfter is garbage, but fenBefore + moveUCI still identify the hung knight.
        let before = "4k3/8/8/4p3/8/1N6/8/4K3 w - - 0 1"
        let text = MoveCommentTemplates.comment(
            fenBefore: before, fenAfter: "garbage", moveUCI: "b3d4", moveSAN: "Nd4",
            classification: "blunder", betterMoveSAN: nil, evalAfter: nil)
        #expect(text.lowercased().contains("hanging"))
    }

    @Test func unknownClassificationFallsBackGenerically() {
        #expect(quiet(classification: "brilliant")
            == "A reasonable move — keep building your position.")
    }

    // MARK: Determinism

    @Test func fixedInputsAlwaysProduceTheSameOutput() {
        let a = quiet(classification: "blunder", betterMoveSAN: "Nf3", evalAfter: "#-2")
        for _ in 0..<5 {
            #expect(quiet(classification: "blunder", betterMoveSAN: "Nf3", evalAfter: "#-2") == a)
        }
    }
}
