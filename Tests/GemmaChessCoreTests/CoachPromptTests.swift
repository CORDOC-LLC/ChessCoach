//  CoachPromptTests.swift
//  Covers U13 test scenarios from the implementation plan.

import Testing
@testable import GemmaChessCore

@Suite("Coach: engine facts text")
struct EngineFactsTests {

    @Test("best line + near-best alternatives within the gap are listed; far ones dropped")
    func bestAndAlternatives() {
        let info = CoachLineInfo(
            bestSan: "Nf3",
            eval: "±0.30",
            winPercent: 55.0,
            lineSan: ["Nf3", "Nc6", "Bb5"],
            alternatives: [
                CoachAltLine(firstSan: "Bc4", eval: "±0.20", winPercent: 53.0), // gap 2 <= 5 -> in
                CoachAltLine(firstSan: "d4", eval: "±0.10", winPercent: 49.0),  // gap 6 > 5 -> out
            ]
        )
        let text = CoachPromptBuilder.engineFactsText(info)
        #expect(text != nil)
        let t = text!
        #expect(t.contains("Best move in this position: Nf3"))
        #expect(t.contains("principal line: Nf3 Nc6 Bb5."))
        #expect(t.contains("Bc4 (eval ±0.20, win 53.0%)"))
        #expect(!t.contains("d4 (eval"))               // beyond the 5-point gap
        #expect(t.contains("within 5 win%-points"))    // gap formatted with :g
    }

    @Test("a blunder move includes classification, the better move, and the refutation")
    func blunderMove() {
        let info = CoachLineInfo(
            bestSan: "c3",
            eval: "+3.70",
            winPercent: 90.0,
            lineSan: ["c3"],
            move: CoachMoveInfo(
                moveSan: "Nf3",
                classification: "blunder",
                winBefore: 80.8,
                winAfter: 56.9,
                winSwing: 23.9,
                isEngineBest: false,
                betterMoveSan: "c3",
                refutationLineSan: ["Nxf3+", "Qxf3"]
            )
        )
        let t = CoachPromptBuilder.engineFactsText(info)!
        #expect(t.contains("The move Nf3 is classified a blunder"))
        #expect(t.contains("win 80.8% → 56.9%, a drop of 23.9"))
        #expect(t.contains("The engine prefers c3 instead."))
        #expect(t.contains("Best reply after it: Nxf3+ Qxf3."))
    }

    @Test("engine-best move says so and names no 'better' move")
    func engineBestMove() {
        let info = CoachLineInfo(
            bestSan: "Qxd5", eval: "+1.20", winPercent: 70.0, lineSan: ["Qxd5"],
            move: CoachMoveInfo(moveSan: "Qxd5", classification: "best",
                                winBefore: 70.0, winAfter: 70.0, winSwing: 0.0,
                                isEngineBest: true)
        )
        let t = CoachPromptBuilder.engineFactsText(info)!
        #expect(t.contains("It is the engine's top choice."))
        #expect(!t.contains("The engine prefers"))
    }

    @Test("empty info yields nil")
    func emptyInfo() {
        let info = CoachLineInfo(bestSan: nil, eval: "", winPercent: 0, lineSan: [])
        #expect(CoachPromptBuilder.engineFactsText(info) == nil)
    }

    @Test("includeBestLine:false emits only the move verdict (no second best-move line)")
    func moveOnlyFacts() {
        let info = CoachLineInfo(
            bestSan: "c3", eval: "+3.70", winPercent: 90.0, lineSan: ["c3"],
            move: CoachMoveInfo(moveSan: "Nf3", classification: "blunder",
                                winBefore: 80.8, winAfter: 56.9, winSwing: 23.9,
                                isEngineBest: false, betterMoveSan: "c3")
        )
        let t = CoachPromptBuilder.engineFactsText(info, includeBestLine: false)!
        #expect(t.contains("The move Nf3 is classified a blunder"))
        #expect(!t.contains("Best move in this position"))   // no duplicate best-move line
    }
}

@Suite("Coach: chat prompt composition")
struct ChatPromptTests {

    @Test("'what should I do' routes current-position facts under CURRENT analysis")
    func currentFactsRouting() {
        let p = CoachPromptBuilder.chatPrompt(
            question: "What should I do here?",
            fen: "8/8/8/8/8/8/8/8 w - - 0 1",
            currentFacts: "- Best move for the side to move: Re1",
            depth: 18
        )
        #expect(p.contains("Current position the user is viewing (FEN): 8/8/8/8/8/8/8/8 w - - 0 1"))
        #expect(p.contains("Engine analysis of the CURRENT position the user now faces (Stockfish depth 18):"))
        #expect(p.contains("- Best move for the side to move: Re1"))
        #expect(p.hasSuffix("User question: What should I do here?"))
    }

    @Test("'why is this bad' with a distinct origin routes move facts and cites the origin FEN")
    func moveFactsRouting() {
        let p = CoachPromptBuilder.chatPrompt(
            question: "Why is Nf3 bad?",
            fen: "current-fen",
            lastMove: "Nf3",
            moveFen: "origin-fen",
            moveFacts: "- The move Nf3 is classified a blunder"
        )
        #expect(p.contains("The move under review is Nf3, which the user played from the position FEN origin-fen"))
        #expect(p.contains("Engine analysis of the move Nf3:"))
        #expect(p.contains("- The move Nf3 is classified a blunder"))
    }

    @Test("player side framing names the user's colour and the engine opponent")
    func playerSideFraming() {
        let white = CoachPromptBuilder.chatPrompt(question: "q", playerSide: .white)
        #expect(white.contains("The user is playing the White pieces against a computer opponent (Black)."))
        #expect(white.contains("'You'/'your' always refers to the White player"))

        let black = CoachPromptBuilder.chatPrompt(question: "q", playerSide: .black)
        #expect(black.contains("The user is playing the Black pieces against a computer opponent (White)."))

        // Absent by default, so non-Play callers are unaffected.
        let none = CoachPromptBuilder.chatPrompt(question: "q")
        #expect(!none.contains("against a computer opponent"))
    }

    @Test("move available at the current board uses the 'available in the current position' phrasing")
    func moveAtCurrentBoard() {
        let p = CoachPromptBuilder.chatPrompt(
            question: "Why is Nf3 bad?", fen: "fen", lastMove: "Nf3", moveFen: "fen"
        )
        #expect(p.contains("The move in question is Nf3, available in the current position."))
        #expect(!p.contains("from FEN"))
    }

    @Test("profile text included only when provided; speed context only when known")
    func optionalContext() {
        let without = CoachPromptBuilder.chatPrompt(question: "q")
        #expect(!without.contains("play history"))
        #expect(without == "User question: q")  // nothing else when no context supplied

        let with = CoachPromptBuilder.chatPrompt(
            question: "q",
            profileFacts: "You hang pieces under time pressure.",
            speedContext: "This is a blitz game."
        )
        #expect(with.contains("This is a blitz game."))
        #expect(with.contains("Background on the user's play history"))
        #expect(with.contains("You hang pieces under time pressure."))
    }

    @Test("persona instructions carry the grounding + no-UI rules; user prompt stays clean")
    func personaSeparation() {
        #expect(CoachPromptBuilder.chatInstructions.contains("TRUST it, do not recompute"))
        #expect(CoachPromptBuilder.chatInstructions.contains("do NOT mention the web board"))
        // The per-question prompt must not carry persona/UI text.
        let p = CoachPromptBuilder.chatPrompt(question: "best move?", currentFacts: "- Best move ...")
        #expect(!p.contains("web board"))
        #expect(!p.contains("chess coach"))
    }
}

@Suite("Coach: game summary facts")
struct GameFactsTests {

    @Test("flagged moves listed worst-first with accuracy and opponent accuracy")
    func flaggedMoves() {
        let input = CoachGameInput(
            white: "alice", black: "bob", result: "1-0", opening: "Italian Game",
            speed: "blitz", player: .white, accuracyWhite: 92.7, accuracyBlack: 81.0,
            mistakes: [
                CoachFlaggedMove(moveNumber: 10, color: .white, moveSan: "Qf3",
                                 classification: "mistake", winBefore: 95, winAfter: 85,
                                 winSwing: 10, bestMoveSan: "Bd3", comment: "Drops the initiative."),
                CoachFlaggedMove(moveNumber: 4, color: .white, moveSan: "Nf3",
                                 classification: "blunder", winBefore: 80.8, winAfter: 56.9,
                                 winSwing: 23.9, bestMoveSan: "c3", comment: "Allows a fork."),
            ]
        )
        let t = CoachPromptBuilder.gameFactsText(input)
        #expect(t.contains("Reviewing White. Accuracy: 92.7% (opponent 81.0%)."))
        #expect(t.contains("Italian Game"))
        // worst-first: the 23.9-swing blunder (move 4) precedes the 10-swing mistake (move 10)
        let blunderIdx = t.range(of: "4.Nf3")!.lowerBound
        let mistakeIdx = t.range(of: "10.Qf3")!.lowerBound
        #expect(blunderIdx < mistakeIdx)
        #expect(t.contains("engine preferred c3. Allows a fork."))
    }

    @Test("clean game phrasing when no mistakes; black uses ... move numbering")
    func cleanGameAndBlack() {
        let clean = CoachGameInput(
            white: "a", black: "b", result: "0-1", opening: nil, speed: "rapid",
            player: .black, accuracyWhite: 70, accuracyBlack: 99, mistakes: []
        )
        let t = CoachPromptBuilder.gameFactsText(clean)
        #expect(t.contains("unknown opening"))
        #expect(t.contains("Reviewing Black. Accuracy: 99.0% (opponent 70.0%)."))
        #expect(t.contains("Black made no inaccuracies, mistakes or blunders — a clean game."))

        let withBlackMove = CoachGameInput(
            white: "a", black: "b", result: "0-1", opening: "X", speed: "rapid",
            player: .black, accuracyWhite: 70, accuracyBlack: 80,
            mistakes: [CoachFlaggedMove(moveNumber: 7, color: .black, moveSan: "Qd7",
                                        classification: "mistake", winBefore: 60, winAfter: 48,
                                        winSwing: 12, bestMoveSan: "Be7", comment: "")]
        )
        #expect(CoachPromptBuilder.gameFactsText(withBlackMove).contains("7...Qd7"))
    }
}
