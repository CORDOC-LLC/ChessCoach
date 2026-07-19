//  PuzzleRushSessionTests.swift
//  Drives a Rush run start-to-finish with an injected clock (no real-time
//  waiting): a correct multi-move solve advancing the queue, a wrong answer
//  costing a time penalty and retrying the same puzzle, a penalty that
//  exhausts the clock ending the run, the countdown hitting zero mid-puzzle,
//  the "no downloaded packs" empty state, a restart leaving no stale state,
//  and difficulty-band shuffling for replay variety.

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

    /// Finds a legal move that isn't the g2-g7 mate, from whatever position
    /// `session` is currently in.
    private func aWrongMove(in session: PuzzleRushSession) throws -> (from: Square, to: Square) {
        let dests = ChessLogic.legalDestinations(forFEN: session.fen)
        let g2 = try #require(BoardGeometry.square("g2"))
        let g7 = try #require(BoardGeometry.square("g7"))
        var wrong: (from: Square, to: Square)?
        outer: for (from, tos) in dests {
            for to in tos where !(from == g2 && to == g7) {
                wrong = (from, to); break outer
            }
        }
        return try #require(wrong)
    }

    @Test("a wrong answer costs a time penalty and retries the same puzzle instead of ending the run")
    func wrongAnswerPenalizesAndRetries() throws {
        let t0 = Date()
        let session = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])
        #expect(session.remainingSeconds == 60)

        let move = try aWrongMove(in: session)
        session.tap(move.from)
        session.tap(move.to)

        #expect(session.isActive)   // the run continues
        #expect(session.hasEnded == false)
        #expect(session.endReason == nil)
        #expect(session.correctCount == 0)
        #expect(session.wrongAttempts == 1)
        #expect(session.justPenalized)
        #expect(session.remainingSeconds == 50)   // 60 - the 10s penalty
        #expect(session.currentPuzzle?.id == mateIn1A.id)   // same puzzle, restarted

        // The next tap (a fresh attempt) clears the transient penalty flag.
        session.tap(move.from)
        #expect(session.justPenalized == false)
    }

    @Test("a wrong-answer penalty that exhausts the clock ends the run via timeExpired")
    func wrongAnswerPenaltyCanExhaustClock() throws {
        let t0 = Date()
        // Only 5 seconds on the clock -- a single 10s penalty must end the run.
        let session = PuzzleRushSession(durationSeconds: 5, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        let move = try aWrongMove(in: session)
        session.tap(move.from)
        session.tap(move.to)

        #expect(session.isActive == false)
        #expect(session.endReason == .timeExpired)
        #expect(session.wrongAttempts == 1)
        #expect(session.remainingSeconds == 0)
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
        // Exhaust the clock via a penalty so the run actually ends.
        let session = PuzzleRushSession(durationSeconds: 5, now: fixedClock(t0))
        session.start(puzzles: [mateIn1A, mateIn1B])

        let move = try aWrongMove(in: session)
        session.tap(move.from)
        session.tap(move.to)
        #expect(session.endReason == .timeExpired)
        #expect(session.wrongAttempts == 1)

        // Restart from scratch, with a fresh duration.
        let restarted = PuzzleRushSession(durationSeconds: 60, now: fixedClock(t0))
        restarted.start(puzzles: [mateIn1A, mateIn1B])

        #expect(restarted.isActive)
        #expect(restarted.endReason == nil)
        #expect(restarted.correctCount == 0)
        #expect(restarted.wrongAttempts == 0)
        #expect(restarted.justPenalized == false)
        #expect(restarted.currentPuzzle?.id == mateIn1A.id)
        #expect(restarted.remainingSeconds == 60)
    }

    @Test("loadPuzzlePool orders puzzles difficulty-ascending across packs")
    func orderIsDifficultyAscending() {
        let ordered = PuzzleRushSession.order([mateIn1B, mateIn1A])
        #expect(ordered.map(\.id) == [mateIn1A.id, mateIn1B.id])
    }

    @Test("order shuffles within a difficulty band but keeps bands ascending")
    func orderShufflesWithinBand() {
        // Five puzzles all in the same 100-point band (rating/100 == 12),
        // plus one clearly higher-rated puzzle -- the band should shuffle
        // relative to itself across generators, while the higher band always
        // sorts after it.
        let sameBand = (0..<5).map { i in
            Puzzle(id: "band-\(i)", fen: mateIn1A.fen, moves: mateIn1A.moves, rating: 1200 + i, themes: [])
        }
        let higher = Puzzle(id: "higher", fen: mateIn1A.fen, moves: mateIn1A.moves, rating: 1900, themes: [])
        let all = sameBand + [higher]

        var seedA = SeededGenerator(seed: 1)
        var seedB = SeededGenerator(seed: 2)
        let orderedA = PuzzleRushSession.order(all, using: &seedA)
        let orderedB = PuzzleRushSession.order(all, using: &seedB)

        #expect(orderedA.last?.id == "higher")   // higher band always last
        #expect(orderedB.last?.id == "higher")
        #expect(Set(orderedA.map(\.id)) == Set(all.map(\.id)))   // same puzzles, no loss
        #expect(orderedA.map(\.id) != orderedB.map(\.id))   // different generators, different order
    }
}

/// A tiny deterministic RNG so shuffle tests don't depend on real randomness
/// or on `SystemRandomNumberGenerator`'s (unspecified) behavior.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xdead_beef : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
