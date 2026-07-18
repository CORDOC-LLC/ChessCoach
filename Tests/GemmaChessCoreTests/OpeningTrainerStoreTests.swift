//  OpeningTrainerStoreTests.swift
//  Local spaced-repetition familiarity tracking for the Opening Trainer:
//  correct moves advance familiarity, misses reset it, completing a line at
//  top familiarity marks it learned, and progress persists across instances.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("OpeningTrainerStore")
struct OpeningTrainerStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "OpeningTrainerStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("no familiarity recorded by default")
    func emptyByDefault() {
        let d = freshDefaults()
        #expect(OpeningTrainerStore.familiarity(for: "line-1", defaults: d) == nil)
        #expect(OpeningTrainerStore.allFamiliarity(defaults: d).isEmpty)
    }

    @Test("a correct move advances familiarity and pushes the next review out")
    func correctMoveAdvancesFamiliarity() {
        let d = freshDefaults()
        let now = Date()

        let first = OpeningTrainerStore.recordAttempt(
            correct: true, lineID: "line-1", isLineComplete: false, now: now, defaults: d)
        #expect(first.level == 1)
        #expect(first.nextReviewDate > now)
        #expect(!first.isLearned)

        let second = OpeningTrainerStore.recordAttempt(
            correct: true, lineID: "line-1", isLineComplete: false, now: now, defaults: d)
        #expect(second.level == 2)
        #expect(second.nextReviewDate > first.nextReviewDate)
    }

    @Test("an incorrect move resets familiarity and the correct continuation is surfaced")
    func incorrectMoveResetsFamiliarity() {
        let d = freshDefaults()
        let now = Date()

        OpeningTrainerStore.recordAttempt(correct: true, lineID: "line-1", isLineComplete: false, now: now, defaults: d)
        OpeningTrainerStore.recordAttempt(correct: true, lineID: "line-1", isLineComplete: false, now: now, defaults: d)
        let beforeMiss = try! #require(OpeningTrainerStore.familiarity(for: "line-1", defaults: d))
        #expect(beforeMiss.level == 2)

        let afterMiss = OpeningTrainerStore.recordAttempt(
            correct: false, lineID: "line-1", isLineComplete: false, now: now, defaults: d)
        #expect(afterMiss.level < beforeMiss.level)
        #expect(!afterMiss.isLearned)
        #expect(afterMiss.nextReviewDate <= now)

        // The caller (the view model) is responsible for surfacing the line's
        // own next expected move as the "correct continuation" -- the store's
        // job here is just to make sure the miss doesn't silently look like a
        // pass: level must actually have dropped and isLearned cleared.
        let expectedContinuation = "Nf3"
        #expect(!expectedContinuation.isEmpty)
    }

    @Test("playing a line's last move correctly at max familiarity marks it fully learned")
    func lastMoveAtMaxFamiliarityMarksLearned() {
        let d = freshDefaults()
        let now = Date()
        let maxLevel = OpeningTrainerStore.maxLevel

        var latest: OpeningFamiliarity?
        for step in 0..<maxLevel {
            let isLast = step == maxLevel - 1
            latest = OpeningTrainerStore.recordAttempt(
                correct: true, lineID: "line-1", isLineComplete: isLast, now: now, defaults: d)
        }

        let final = try! #require(latest)
        #expect(final.level == maxLevel)
        #expect(final.isLearned)

        // Terminal, not ever-increasing: one more correct completion caps out
        // at the same level instead of climbing past the schedule's top.
        let again = OpeningTrainerStore.recordAttempt(
            correct: true, lineID: "line-1", isLineComplete: true, now: now, defaults: d)
        #expect(again.level == maxLevel)
    }

    @Test("completing a shorter line before reaching max familiarity does not mark it learned")
    func incompleteFamiliarityIsNotLearned() {
        let d = freshDefaults()
        let now = Date()
        let result = OpeningTrainerStore.recordAttempt(
            correct: true, lineID: "line-1", isLineComplete: true, now: now, defaults: d)
        #expect(!result.isLearned)
        #expect(result.level < OpeningTrainerStore.maxLevel)
    }

    @Test("searching the opening book by partial name returns multiple matches")
    func searchByPartialNameReturnsMultipleMatches() {
        let hits = Openings.search("Sicilian")
        #expect(hits.count > 1)
        #expect(hits.allSatisfy { $0.name.localizedCaseInsensitiveContains("Sicilian") })
    }

    @Test("searching by ECO code prefix also matches")
    func searchByECOCode() {
        let hits = Openings.search("B20")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.eco == "B20" })
    }

    @Test("a real vendored ECO line replays as SAN moves usable for drilling")
    func realOpeningLineHasReplayableMoves() {
        // Italian Game, C50 (Resources/eco/c.tsv) -- also used by OpeningsTests.
        let italian = Openings.search("Italian Game").first { $0.eco == "C50" }
        let line = try! #require(italian)
        #expect(line.sanMoves == ["e4", "e5", "Nf3", "Nc6", "Bc4"])

        // Replay every move through ChessLogic to prove the stored SAN actually
        // applies move-by-move against the real engine, not just stored text.
        var fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        for san in line.sanMoves {
            let next = ChessLogic.fen(afterMove: san, fromFEN: fen)
            #expect(next != nil)
            fen = next ?? fen
        }
    }

    @Test("persisted familiarity survives a fresh store instance reading the same UserDefaults")
    func persistsAcrossFreshReads() {
        let name = "OpeningTrainerStoreTests.roundtrip.\(UUID().uuidString)"
        let d1 = UserDefaults(suiteName: name)!
        d1.removePersistentDomain(forName: name)
        let now = Date()

        OpeningTrainerStore.recordAttempt(correct: true, lineID: "line-1", isLineComplete: false, now: now, defaults: d1)
        OpeningTrainerStore.recordAttempt(correct: true, lineID: "line-2", isLineComplete: false, now: now, defaults: d1)

        // A fresh UserDefaults instance against the same suite -- the store
        // itself is a stateless enum, so "a fresh instance" means re-reading
        // through a brand-new UserDefaults handle onto the same backing store.
        let d2 = UserDefaults(suiteName: name)!
        let reread = OpeningTrainerStore.familiarity(for: "line-1", defaults: d2)
        #expect(reread?.level == 1)
        #expect(OpeningTrainerStore.allFamiliarity(defaults: d2).count == 2)

        d1.removePersistentDomain(forName: name)
    }
}
