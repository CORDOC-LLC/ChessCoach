//  CoachPromptTests.swift
//  `CoachPrompt.swift` used to hold the coach personas and text-formatting
//  logic (now server-side, plan 2026-07-21-002 U1/U2) -- what's left are the
//  plain `Codable` fact-shaping structs `CoachOrchestrator` sends as JSON.
//  These tests pin their wire field names/shapes exactly, since a drift here
//  would silently break `/api/coach`'s contract.

import Foundation
import Testing
@testable import GemmaChessCore

@Suite("Coach: fact structs are Codable with the expected wire field names")
struct CoachFactStructWireShapeTests {

    @Test("CoachLineInfo encodes with camelCase field names matching the wire contract")
    func coachLineInfoFieldNames() throws {
        let info = CoachLineInfo(
            bestSan: "Nf3", eval: "+0.30", winPercent: 55.0, lineSan: ["Nf3", "Nc6"],
            alternatives: [CoachAltLine(firstSan: "Bc4", eval: "+0.20", winPercent: 53.0)],
            move: CoachMoveInfo(
                moveSan: "g4", classification: "blunder", winBefore: 80.8, winAfter: 56.9,
                winSwing: 23.9, isEngineBest: false, betterMoveSan: "c3",
                refutationLineSan: ["Nxf3+", "Qxf3"]
            )
        )
        let data = try JSONEncoder().encode(info)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["bestSan"] as? String == "Nf3")
        #expect(json["winPercent"] as? Double == 55.0)
        #expect(json["lineSan"] as? [String] == ["Nf3", "Nc6"])
        let move = try #require(json["move"] as? [String: Any])
        #expect(move["moveSan"] as? String == "g4")
        #expect(move["isEngineBest"] as? Bool == false)
        #expect(move["betterMoveSan"] as? String == "c3")
        #expect(move["refutationLineSan"] as? [String] == ["Nxf3+", "Qxf3"])

        // Round-trips.
        let decoded = try JSONDecoder().decode(CoachLineInfo.self, from: data)
        #expect(decoded == info)
    }

    @Test("CoachSide encodes as lowercase \"white\"/\"black\", not a Swift case name")
    func coachSideEncoding() throws {
        let data = try JSONEncoder().encode(CoachSide.white)
        #expect(String(data: data, encoding: .utf8) == "\"white\"")
        let data2 = try JSONEncoder().encode(CoachSide.black)
        #expect(String(data: data2, encoding: .utf8) == "\"black\"")
    }

    @Test("CoachFlaggedMove/CoachGameInput round-trip with the wire's field names")
    func gameInputRoundTrips() throws {
        let input = CoachGameInput(
            white: "alice", black: "bob", result: "1-0", opening: "Italian Game", speed: "blitz",
            player: .white, accuracyWhite: 92.7, accuracyBlack: 81.0,
            mistakes: [CoachFlaggedMove(
                moveNumber: 4, color: .white, moveSan: "Nf3", classification: "blunder",
                winBefore: 80.8, winAfter: 56.9, winSwing: 23.9, bestMoveSan: "c3",
                comment: "Allows a fork.",
                fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"
            )]
        )
        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(CoachGameInput.self, from: data)
        #expect(decoded == input)

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["player"] as? String == "white")
        let mistake = try #require((json["mistakes"] as? [[String: Any]])?.first)
        #expect(mistake["color"] as? String == "white")
        #expect(mistake["bestMoveSan"] as? String == "c3")
        #expect(mistake["fen"] as? String == "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3")
    }

    @Test("CoachFlaggedMove decodes fen as nil when absent (older data predating this field)")
    func coachFlaggedMoveBackwardCompatibleDecode() throws {
        let json = Data("""
        {"moveNumber":4,"color":"white","moveSan":"Nf3","classification":"blunder",
         "winBefore":80.8,"winAfter":56.9,"winSwing":23.9,"bestMoveSan":"c3","comment":"Allows a fork."}
        """.utf8)
        let decoded = try JSONDecoder().decode(CoachFlaggedMove.self, from: json)
        #expect(decoded.fen == nil)
        #expect(decoded.moveSan == "Nf3")
    }

    @Test("PlayMoveRecord round-trips, with bestUCI/fen decoding nil when absent (older saved games)")
    func playMoveRecordBackwardCompatibleDecode() throws {
        let json = Data("""
        {"moveNumber":1,"san":"d4","classification":"best","winBefore":52,"winAfter":52}
        """.utf8)
        let decoded = try JSONDecoder().decode(CoachPromptBuilder.PlayMoveRecord.self, from: json)
        #expect(decoded.bestUCI == nil)
        #expect(decoded.fen == nil)
        #expect(decoded.san == "d4")
    }

    @Test("PlayMoveRecord encodes fen with the wire's field name when present")
    func playMoveRecordFenEncodes() throws {
        let record = CoachPromptBuilder.PlayMoveRecord(
            moveNumber: 1, san: "d4", classification: "best",
            winBefore: 52, winAfter: 52, betterSan: nil,
            bestUCI: "d2d4", fen: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1")
        let data = try JSONEncoder().encode(record)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["fen"] as? String == "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1")

        let decoded = try JSONDecoder().decode(CoachPromptBuilder.PlayMoveRecord.self, from: data)
        #expect(decoded == record)
    }
}
