//  PuzzleRushSessionTests.swift
//  Drives a Rush run start-to-finish with an injected clock (no real-time
//  waiting): a correct multi-move solve advancing the queue, a wrong answer
//  ending the run immediately, the countdown hitting zero mid-puzzle, the
//  "no downloaded packs" empty state, and a restart leaving no stale state.

import Testing
import Foundation
import ChessKit
@testable import GemmaChessCore

@MainActor
@Suite("PuzzleRushSession")
struct PuzzleRushSessionTests {

    // Real 2-ply mate-in-1 puzzles from PuzzleData/packs/mateIn1.json (same
    // fixture PuzzleViewModelTests uses): the setup move auto-plays, then the
    // solver has one move to find.
    private let mateIn1A = Puzzle(
        id: "00lhe",
        fen: "r2q1b1k/ppp3Bp/3pPp2/2n1n3/4P2P/1B3P2/PPP3Q1/2K3RR b - - 0 23",
        moves: ["f8g7", "g2g7"],
        rating: 399,
        themes: ["mateIn1"]
    )
    private let mateIn1B = Puzzle(
        id: "second",
        fen: "r2q1b1k/ppp3Bp/3pPp2/2n1n3/4P2P/1B3P2/PPP3Q1/2K3RR b - - 0 23",
        moves: ["f8g7", "g2g7"],
        rating: 1400,
        themes: ["mateIn1"]
    )

    private func fixedClock(_ date: Date) -> () -> Date { { date } }

    @Test("a correct answer advances to the next puzzle and increments the running count")
    func correctAnswerAdvances() throws {
        let t0 = Date()
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        #expect(session.isActive)
        #expect(session.currentPuzzle?.id == mateIn1A.id)   // lower-rated puzzle first

        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        session.tap(g2)
        session.tap(g7)

        #expect(session.isActive)
        #expect(session.correctCount == 1)
        #expect(session.currentPuzzle?.id == mateIn1B.id)
        #expect(session.endReason == nil)
    }

    @Test("a wrong answer ends the session immediately and records the final score")
    func wrongAnswerEndsSession() throws {
        let t0 = Date()
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        // Any legal move that isn't the g2-g7 mate.
        let dests = ChessLogic.legalDestinations(forFEN: session.fen)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        let move = try #require(wrong)

        session.tap(move.from)
        session.tap(move.to)

        #expect(session.isActive == false)
        #expect(session.endReason == .wrongAnswer)
        #expect(session.correctCount == 0)   // final score: zero solved this run
        #expect(session.hasEnded)
    }

    @Test("the timer reaching zero mid-puzzle ends the session and records the final score")
    func timerExpiryEndsSession() throws {
        let t0 = Date()
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        session.tap(g2)
        session.tap(g7)
        #expect(session.correctCount == 1)

        // Time runs out mid-way through the second puzzle -- no answer given.
        session.tick(at: t0.addingTimeInterval(61))

        #expect(session.isActive == false)
        #expect(session.endReason == .timeExpired)
        #expect(session.correctCount == 1)   // final score preserved at time of expiry
        #expect(session.remainingSeconds == 0)
    }

    @Test("starting with no downloaded puzzles reports a clear empty state instead of crashing")
    func emptyPoolReportsDownloadFirstState() {
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(Date()))
        session.start(puzzles: [])

        #expect(session.isEmpty)
        #expect(session.isActive == false)
        #expect(session.currentPuzzle == nil)
        #expect(session.endReason == nil)   // empty is distinct from "ended"
        #expect(session.hasEnded == false)
    }

    @Test("restarting after a run ended starts fresh with no stale state")
    func restartClearsStaleState() throws {
        let t0 = Date()
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        // End the run with a wrong answer.
        let dests = ChessLogic.legalDestinations(forFEN: session.fen)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        let move = try #require(wrong)
        session.tap(move.from)
        session.tap(move.to)
        #expect(session.endReason == .wrongAnswer)

        // Restart from scratch.
        session.start(puzzles: [mateIn1A, mateIn1B])

        #expect(session.isActive)
        #expect(session.endReason == nil)
        #expect(session.correctCount == 0)
        #expect(session.currentPuzzle?.id == mateIn1A.id)
        #expect(session.remainingSeconds == 60)
    }

    @Test("loadPuzzlePool orders puzzles difficulty-ascending across packs")
    func orderIsDifficultyAscending() {
        let ordered = PuzzleRushSession.order([mateIn1B, mateIn1A])
        #expect(ordered.map(\.id) == [mateIn1A.id, mateIn1B.id])
    }
}
