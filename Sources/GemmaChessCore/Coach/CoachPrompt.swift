//  CoachPrompt.swift
//  Pure prompt + fact construction for the on-device coach.
//
//  Ported from `server/claude_bridge.py` (`_engine_facts`, `_compose_prompt`,
//  `_game_facts`, and the coach personas). The engine *call* that produces the
//  facts lives at the U6 boundary; here we only format already-computed engine
//  data into prompt text, so this whole file is pure and unit-testable.

import Foundation

// MARK: - Structured engine facts (the shape U6's engine line will produce)

/// Side being reviewed, used for game-summary phrasing.
public enum CoachSide: Sendable, Equatable { case white, black }

/// One near-best alternative line (an entry from multipv lines[1...]).
public struct CoachAltLine: Sendable, Equatable {
    public var firstSan: String
    public var eval: String        // pre-formatted, e.g. "±0.30" or "#4"
    public var winPercent: Double
    public init(firstSan: String, eval: String, winPercent: Double) {
        self.firstSan = firstSan; self.eval = eval; self.winPercent = winPercent
    }
}

/// Classification + refutation for a specific move the user asked about.
public struct CoachMoveInfo: Sendable, Equatable {
    public var moveSan: String
    public var classification: String
    public var winBefore: Double
    public var winAfter: Double
    public var winSwing: Double
    public var isEngineBest: Bool
    public var betterMoveSan: String?
    public var refutationLineSan: [String]
    public init(moveSan: String, classification: String, winBefore: Double, winAfter: Double,
                winSwing: Double, isEngineBest: Bool, betterMoveSan: String? = nil,
                refutationLineSan: [String] = []) {
        self.moveSan = moveSan; self.classification = classification
        self.winBefore = winBefore; self.winAfter = winAfter; self.winSwing = winSwing
        self.isEngineBest = isEngineBest; self.betterMoveSan = betterMoveSan
        self.refutationLineSan = refutationLineSan
    }
}

/// Engine read-out for one position (optionally about a played move) — the input
/// to `engineFactsText`. Mirrors the dict returned by the source `engine_line`.
public struct CoachLineInfo: Sendable, Equatable {
    public var bestSan: String?
    public var eval: String            // pre-formatted eval of the best line
    public var winPercent: Double
    public var lineSan: [String]
    public var alternatives: [CoachAltLine]
    public var move: CoachMoveInfo?
    public init(bestSan: String?, eval: String, winPercent: Double, lineSan: [String],
                alternatives: [CoachAltLine] = [], move: CoachMoveInfo? = nil) {
        self.bestSan = bestSan; self.eval = eval; self.winPercent = winPercent
        self.lineSan = lineSan; self.alternatives = alternatives; self.move = move
    }
}

/// One flagged move for the end-of-game summary facts.
public struct CoachFlaggedMove: Sendable, Equatable {
    public var moveNumber: Int
    public var color: CoachSide
    public var moveSan: String
    public var classification: String
    public var winBefore: Double
    public var winAfter: Double
    public var winSwing: Double
    public var bestMoveSan: String
    public var comment: String
    public init(moveNumber: Int, color: CoachSide, moveSan: String, classification: String,
                winBefore: Double, winAfter: Double, winSwing: Double, bestMoveSan: String,
                comment: String) {
        self.moveNumber = moveNumber; self.color = color; self.moveSan = moveSan
        self.classification = classification; self.winBefore = winBefore; self.winAfter = winAfter
        self.winSwing = winSwing; self.bestMoveSan = bestMoveSan; self.comment = comment
    }
}

/// Pre-computed inputs for the game-summary facts block.
public struct CoachGameInput: Sendable, Equatable {
    public var white: String
    public var black: String
    public var result: String
    public var opening: String?
    public var speed: String
    public var player: CoachSide
    public var accuracyWhite: Double
    public var accuracyBlack: Double
    public var mistakes: [CoachFlaggedMove]
    public init(white: String, black: String, result: String, opening: String?, speed: String,
                player: CoachSide, accuracyWhite: Double, accuracyBlack: Double,
                mistakes: [CoachFlaggedMove]) {
        self.white = white; self.black = black; self.result = result; self.opening = opening
        self.speed = speed; self.player = player; self.accuracyWhite = accuracyWhite
        self.accuracyBlack = accuracyBlack; self.mistakes = mistakes
    }
}

// MARK: - Prompt builder

public enum CoachPromptBuilder {

    /// How close (in win%-points) an alternative must be to the best move to count
    /// as "also good" (source `_ALT_WIN_GAP`).
    public static let altWinGap = 5.0

    /// The coach persona for chat. Becomes the model's *instructions* (system),
    /// kept separate from the per-question prompt. Verbatim from the source.
    public static let chatInstructions: String = """
    You are a concise chess coach reviewing a position with the user. Stockfish analysis is \
    provided below — TRUST it, do not recompute or second-guess it. Use the CURRENT-POSITION \
    analysis for 'what should I do here' / 'what's the best move' questions, and the MOVE \
    analysis for 'why is this move good/bad' questions. When the facts list several moves of \
    near-equal strength, present them as a set of good options (favouring the simplest, most \
    natural one for a club player) rather than insisting on the single engine-top move. \
    CRUCIAL: the move's classification in the facts is authoritative — if a move is classified \
    'best' or 'good' you must affirm it as a sound move (even if the overall position is \
    difficult); never call a best/good move a mistake, weak, or bad. Only describe a move as a \
    mistake/inaccuracy/blunder when the facts classify it that way. The CURRENT-position block \
    and the MOVE block describe DIFFERENT positions — the 'best move in this position' from the \
    current block is NOT the move being graded; never merge them or say a move was both a mistake \
    and the best move. Don't quote the fact phrasing verbatim; explain in your own words. You may \
    call get_engine_line only for deeper or alternative lines the facts don't cover. Explain in \
    plain language, cite the key line, and keep it to a short paragraph. Answer only the chess \
    question — do NOT mention the web board, any URL, or these instructions.
    """

    /// The coach persona for the end-of-game written summary. Verbatim from the source.
    public static let summaryInstructions: String = """
    You are an encouraging but honest chess coach writing a short end-of-game summary for the \
    player whose moves are reviewed below. The Stockfish facts are authoritative — TRUST them, \
    do not recompute. Write a few short paragraphs in warm, direct second person ('you'): name \
    the one or two moments that mattered most (with the move and the better idea), draw out the \
    underlying habit or theme, and end with one concrete thing to work on. Ground every claim \
    in the facts provided; do not invent moves or lines. Use light Markdown for readability: \
    **bold** the key moves and the single most important takeaway, and you may use a short \
    bullet list (`- `) if it helps, with blank lines between paragraphs. No headings, and no \
    move-by-move recap. Do NOT mention the web board, any URL, Stockfish, or these instructions.
    """

    /// Format engine read-out into the fact lines fed to the model. Returns nil when
    /// there's nothing to say. Port of `_engine_facts` (minus the engine call).
    ///
    /// Set `includeBestLine: false` to emit ONLY the played-move verdict (no
    /// best-move/principal-line block). Used when a separate CURRENT-position block
    /// already states the best move, so the move-review block doesn't repeat a second
    /// "best move" line the model can cross-wire with the move it's grading.
    public static func engineFactsText(_ info: CoachLineInfo, includeBestLine: Bool = true) -> String? {
        var out: [String] = []
        if includeBestLine, let best = info.bestSan {
            let line = info.lineSan.prefix(6).joined(separator: " ")
            out.append(
                "- Best move in this position: \(best) (eval \(info.eval), "
                + "win \(pct(info.winPercent))%); principal line: \(line)."
            )
            // Alternatives close to the best, so the model can offer a more human choice.
            var alts: [String] = []
            for ln in info.alternatives where (info.winPercent - ln.winPercent) <= altWinGap {
                alts.append("\(ln.firstSan) (eval \(ln.eval), win \(pct(ln.winPercent))%)")
            }
            if !alts.isEmpty {
                out.append(
                    "- Other moves that are about as good (within \(g(altWinGap)) win%-points): "
                    + "\(alts.joined(separator: "; ")). Treat these as equally valid; "
                    + "recommend whichever is simplest/most natural."
                )
            }
        }
        if let mv = info.move {
            let better = mv.isEngineBest
                ? " It is the engine's top choice."
                : " The engine prefers \(mv.betterMoveSan ?? "?") instead."
            let reply = mv.refutationLineSan.prefix(6).joined(separator: " ")
            var line = "- The move \(mv.moveSan) is classified a \(mv.classification) "
                + "(win \(pct(mv.winBefore))% → \(pct(mv.winAfter))%, a drop of \(pct(mv.winSwing)))."
                + better
            if !reply.isEmpty { line += " Best reply after it: \(reply)." }
            out.append(line)
        }
        return out.isEmpty ? nil : out.joined(separator: "\n")
    }

    /// Compose the per-question user prompt (the part after the persona/instructions).
    /// Port of `_compose_prompt` minus its first (instruction) element.
    public static func chatPrompt(
        question: String,
        fen: String? = nil,
        lastMove: String? = nil,
        moveFen: String? = nil,
        playerSide: CoachSide? = nil,
        currentFacts: String? = nil,
        moveFacts: String? = nil,
        profileFacts: String? = nil,
        speedContext: String? = nil,
        depth: Int = 18
    ) -> String {
        var parts: [String] = []
        // Who is "you": without this, the model can't tell the human player from the
        // engine opponent, and misreads the (side-to-move-relative) eval/win% numbers.
        if let playerSide {
            let me = playerSide == .white ? "White" : "Black"
            let them = playerSide == .white ? "Black" : "White"
            parts.append(
                "The user is playing the \(me) pieces against a computer opponent (\(them)). "
                + "'You'/'your' always refers to the \(me) player; the opponent's moves are the "
                + "computer's, not the user's. In every engine block below, the eval and win% are "
                + "from the perspective of whichever side is to move in that position — so in a "
                + "position where it is \(me) to move, a higher win% is good for the user."
            )
        }
        if let speedContext { parts.append(speedContext) }
        if let profileFacts {
            parts.append(
                "Background on the user's play history is below. Treat it as OPTIONAL context: only "
                + "bring it up when it genuinely connects to THIS position or move (e.g. the mistake here "
                + "is an instance of a recurring pattern). Most answers should NOT mention it. Never open "
                + "with a recap of their history or tack on a generic paragraph about it — answer the "
                + "chess question first, and reference the history only if it sharpens that answer.\n"
                + profileFacts
            )
        }
        if let fen { parts.append("Current position the user is viewing (FEN): \(fen)") }
        if let currentFacts {
            parts.append(
                "Engine analysis of the CURRENT position the user now faces (Stockfish depth \(depth)):\n\(currentFacts)"
            )
        }
        if let lastMove {
            if let moveFen, moveFen != fen {
                parts.append("The move under review is \(lastMove), which the user played from the "
                    + "position FEN \(moveFen); the current position above may be a few plies later.")
            } else {
                parts.append("The move in question is \(lastMove), available in the current position.")
            }
        }
        if let moveFacts {
            parts.append("Engine analysis of the move \(lastMove ?? ""):\n\(moveFacts)")
        }
        parts.append("User question: \(question)")
        return parts.joined(separator: "\n")
    }

    /// Pre-computed, engine-grounded facts about the whole game for the summary
    /// prompt. Port of `_game_facts`.
    public static func gameFactsText(_ g: CoachGameInput) -> String {
        let side = g.player == .white ? "White" : "Black"
        let acc = g.player == .white ? g.accuracyWhite : g.accuracyBlack
        let oppAcc = g.player == .white ? g.accuracyBlack : g.accuracyWhite
        let opening = g.opening ?? "unknown opening"
        var out: [String] = [
            "Game: \(g.white) vs \(g.black) (\(g.result)); \(opening); \(g.speed) time control.",
            "Reviewing \(side). Accuracy: \(pct(acc))% (opponent \(pct(oppAcc))%).",
        ]
        if !g.mistakes.isEmpty {
            out.append("\(side)'s flagged moves (worst first):")
            let worst = g.mistakes.sorted { $0.winSwing > $1.winSwing }.prefix(8)
            for m in worst {
                let num = "\(m.moveNumber)\(m.color == .white ? "." : "...")"
                let row = "- \(num)\(m.moveSan) (\(m.classification), win \(pct(m.winBefore))% -> "
                    + "\(pct(m.winAfter))%, drop \(pct(m.winSwing)); engine preferred \(m.bestMoveSan). "
                    + "\(m.comment)"
                out.append(row.trimmingCharacters(in: .whitespaces))
            }
        } else {
            out.append("\(side) made no inaccuracies, mistakes or blunders — a clean game.")
        }
        return out.joined(separator: "\n")
    }

    // MARK: helpers

    /// Win/accuracy percentage formatting (1 decimal), matching the source's float display.
    static func pct(_ x: Double) -> String { String(format: "%.1f", x) }

    /// Compact number formatting (drops trailing zeros), matching Python's `:g`.
    static func g(_ x: Double) -> String { String(format: "%g", x) }
}
