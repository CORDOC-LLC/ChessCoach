//  EngineLine.swift
//  Single-position engine analysis, port of the source's `server/core/lines.py`.
//  Produces the grounded line for one position and, optionally, the classification
//  + refutation of a candidate move. Its output converts to `CoachLineInfo`, so the
//  coach (U13) is fed exactly these engine facts.

import Foundation

public struct EngineLineReport: Sendable, Equatable {
    public struct SubLine: Sendable, Equatable {
        public var eval: String
        public var winPercent: Double
        public var lineSAN: [String]
        public var lineUCI: [String]
    }
    public struct MoveReport: Sendable, Equatable {
        public var moveSAN: String
        public var moveUCI: String
        public var classification: String
        public var winBefore: Double
        public var winAfter: Double
        public var winSwing: Double
        public var evalAfterCp: Int
        public var evalAfter: String
        public var isEngineBest: Bool
        public var betterMoveSAN: String?
        public var refutationLineSAN: [String]
        public var refutationLineUCI: [String]
    }

    public var fen: String
    public var sideToMove: String      // "white" | "black"
    public var depth: Int
    public var eval: String
    public var evalCp: Int
    public var winPercent: Double
    public var bestSAN: String?
    public var lineSAN: [String]
    public var lineUCI: [String]
    public var lines: [SubLine]        // multipv (best first)
    public var move: MoveReport?
    public var error: String?
}

public enum EngineLine {

    /// Human-readable eval from the side-to-move perspective.
    public static func evalStr(cp: Int?, mate: Int?) -> String {
        if let mate { return mate > 0 ? "#\(mate)" : "#-\(abs(mate))" }
        let pawns = Double(cp ?? 0) / 100.0
        return String(format: "%+.2f", pawns)
    }

    /// Like `evalStr` but for a signed cp that may be a mate-equivalent magnitude.
    public static func evalStrFromSignedCp(_ cp: Int) -> String {
        if abs(cp) >= GCConfig.mateScoreCp { return cp > 0 ? "#" : "#-" }
        return String(format: "%+.2f", Double(cp) / 100.0)
    }

    /// Evaluate a position (optionally after a candidate move). Port of `engine_line`.
    public static func evaluate(
        fen: String,
        move: String? = nil,
        depth: Int = GCConfig.defaultDepth,
        multipv: Int = 1,
        engine: EnginePool = .shared
    ) async throws -> EngineLineReport {
        let base = try await engine.analyse(fen: fen, depth: depth, multipv: max(1, multipv))
        let best = base.best
        let bestLineSAN = ChessLogic.pvToSAN(best.pvUCI, fromFEN: fen)
        let stm = (ChessLogic.sideToMove(forFEN: fen) == .white) ? "white" : "black"

        var report = EngineLineReport(
            fen: fen,
            sideToMove: stm,
            depth: depth,
            eval: evalStr(cp: best.cp, mate: best.mate),
            evalCp: Int(best.signedCp.rounded()),
            winPercent: Evaluation.round1(best.winPercent),
            bestSAN: bestLineSAN.first,
            lineSAN: bestLineSAN,
            lineUCI: Array(best.pvUCI.prefix(12)),
            lines: [],
            move: nil,
            error: nil
        )

        if multipv > 1 {
            report.lines = base.lines.map { ln in
                EngineLineReport.SubLine(
                    eval: evalStr(cp: ln.cp, mate: ln.mate),
                    winPercent: Evaluation.round1(ln.winPercent),
                    lineSAN: ChessLogic.pvToSAN(ln.pvUCI, fromFEN: fen),
                    lineUCI: Array(ln.pvUCI.prefix(12))
                )
            }
        }

        guard let move else { return report }

        // Resolve the candidate move to (uci, san); accept UCI or SAN.
        let moveUCI: String
        let moveSAN: String
        if let san = ChessLogic.san(fromUCI: move, inFEN: fen) {
            moveUCI = move; moveSAN = san
        } else if let uci = ChessLogic.uci(fromSAN: move, inFEN: fen),
                  let san = ChessLogic.san(fromUCI: uci, inFEN: fen) {
            moveUCI = uci; moveSAN = san
        } else {
            report.error = "Illegal or unparseable move '\(move)'"
            return report
        }

        let winBefore = best.winPercent
        guard let afterFEN = ChessLogic.fen(afterMove: moveUCI, fromFEN: fen) else {
            report.error = "Could not apply move '\(move)'"
            return report
        }

        let winAfter: Double
        var refutationSAN: [String] = []
        var refutationUCI: [String] = []
        let afterEvalCp: Int

        switch ChessLogic.status(forFEN: afterFEN) {
        case .checkmate:
            winAfter = 100.0                 // the mover delivered mate
            afterEvalCp = GCConfig.mateScoreCp
        case .stalemate:
            winAfter = 50.0
            afterEvalCp = 0
        default:
            let after = try await engine.analyse(fen: afterFEN, depth: depth, multipv: 1).best
            winAfter = 100.0 - after.winPercent     // back to the mover's perspective
            refutationUCI = Array(after.pvUCI.prefix(12))
            refutationSAN = ChessLogic.pvToSAN(after.pvUCI, fromFEN: afterFEN)
            afterEvalCp = -Int(after.signedCp.rounded())
        }

        let isBest = best.pvUCI.first == moveUCI
        let classification = Evaluation.classify(
            winBefore: winBefore, winAfter: winAfter, isBest: isBest
        ).rawValue

        report.move = EngineLineReport.MoveReport(
            moveSAN: moveSAN,
            moveUCI: moveUCI,
            classification: classification,
            winBefore: Evaluation.round1(winBefore),
            winAfter: Evaluation.round1(winAfter),
            winSwing: Evaluation.round1(winBefore - winAfter),
            evalAfterCp: afterEvalCp,
            evalAfter: evalStrFromSignedCp(afterEvalCp),
            isEngineBest: isBest,
            betterMoveSAN: report.bestSAN,
            refutationLineSAN: refutationSAN,
            refutationLineUCI: refutationUCI
        )
        return report
    }
}

public extension EngineLineReport {
    /// Convert to the coach's fact input, so U13's `engineFactsText` is fed real engine data.
    var coachInfo: CoachLineInfo {
        CoachLineInfo(
            bestSan: bestSAN,
            eval: eval,
            winPercent: winPercent,
            lineSan: lineSAN,
            alternatives: lines.dropFirst().compactMap { ln in
                guard let first = ln.lineSAN.first else { return nil }
                return CoachAltLine(firstSan: first, eval: ln.eval, winPercent: ln.winPercent)
            },
            move: move.map { m in
                CoachMoveInfo(
                    moveSan: m.moveSAN,
                    classification: m.classification,
                    winBefore: m.winBefore,
                    winAfter: m.winAfter,
                    winSwing: m.winSwing,
                    isEngineBest: m.isEngineBest,
                    betterMoveSan: m.betterMoveSAN,
                    refutationLineSan: m.refutationLineSAN
                )
            }
        )
    }
}
