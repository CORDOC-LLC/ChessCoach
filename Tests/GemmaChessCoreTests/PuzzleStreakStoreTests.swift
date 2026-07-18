//  PuzzleStreakStoreTests.swift
//  Consecutive-day puzzle streak, exercised with an injected fixed
//  Calendar/date sequence -- no reliance on wall-clock time.

import Testing
import Foundation
@testable import GemmaChessCore

@Suite("PuzzleStreakStore")
struct PuzzleStreakStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "PuzzleStreakStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, calendar: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }

    @Test("no streak before any solve")
    func zeroByDefault() {
        let d = freshDefaults()
        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 0)
        #expect(PuzzleStreakStore.lastSolvedDate(defaults: d) == nil)
    }

    @Test("first-ever solve sets streak to 1")
    func firstSolve() {
        let d = freshDefaults()
        let cal = utcCalendar
        let day1 = date(2026, 7, 1, calendar: cal)

        let streak = PuzzleStreakStore.recordSolve(now: day1, calendar: cal, defaults: d)

        #expect(streak == 1)
        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 1)
    }

    @Test("solve on the following day increments the streak")
    func consecutiveDayIncrements() {
        let d = freshDefaults()
        let cal = utcCalendar
        let day1 = date(2026, 7, 1, calendar: cal)
        let day2 = date(2026, 7, 2, calendar: cal)

        PuzzleStreakStore.recordSolve(now: day1, calendar: cal, defaults: d)
        let streak = PuzzleStreakStore.recordSolve(now: day2, calendar: cal, defaults: d)

        #expect(streak == 2)
    }

    @Test("second solve on the same day does not double-count")
    func sameDayNoDoubleCount() {
        let d = freshDefaults()
        let cal = utcCalendar
        let morning = date(2026, 7, 1, hour: 9, calendar: cal)
        let evening = date(2026, 7, 1, hour: 21, calendar: cal)

        PuzzleStreakStore.recordSolve(now: morning, calendar: cal, defaults: d)
        let streak = PuzzleStreakStore.recordSolve(now: evening, calendar: cal, defaults: d)

        #expect(streak == 1)
        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 1)
    }

    @Test("solve after a missed day resets the streak to 1")
    func gapResetsStreak() {
        let d = freshDefaults()
        let cal = utcCalendar
        let day1 = date(2026, 7, 1, calendar: cal)
        let day2 = date(2026, 7, 2, calendar: cal)
        let day5 = date(2026, 7, 5, calendar: cal) // gap of 3 days

        PuzzleStreakStore.recordSolve(now: day1, calendar: cal, defaults: d)
        PuzzleStreakStore.recordSolve(now: day2, calendar: cal, defaults: d)
        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 2)

        let streak = PuzzleStreakStore.recordSolve(now: day5, calendar: cal, defaults: d)

        #expect(streak == 1)
    }

    @Test("day boundary uses the injected non-UTC device calendar, not raw UTC")
    func nonUTCDayBoundary() {
        let d = freshDefaults()
        // A calendar in a fixed timezone well ahead of UTC (UTC+13, no DST
        // ambiguity since it's a fixed offset rather than a named region).
        // The two solves below fall on two *different* UTC calendar days,
        // but the *same* local calendar day -- a correct implementation
        // must use the injected calendar's day boundary and treat this as
        // one day (no-op on the second solve), not two.
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeZone(secondsFromGMT: 13 * 3600)!

        var firstComps = DateComponents()
        firstComps.timeZone = TimeZone(identifier: "UTC")!
        firstComps.year = 2026; firstComps.month = 7; firstComps.day = 1
        firstComps.hour = 23 // UTC July 1, 23:00 == local July 2, 12:00
        let firstSolve = localCal.date(from: firstComps)!

        var secondComps = DateComponents()
        secondComps.timeZone = TimeZone(identifier: "UTC")!
        secondComps.year = 2026; secondComps.month = 7; secondComps.day = 2
        secondComps.hour = 1 // UTC July 2, 01:00 == local July 2, 14:00
        let secondSolve = localCal.date(from: secondComps)!

        // Sanity: different UTC calendar days, but the same local calendar
        // day under `localCal`.
        let utc = utcCalendar
        #expect(!utc.isDate(firstSolve, inSameDayAs: secondSolve))
        #expect(localCal.isDate(firstSolve, inSameDayAs: secondSolve))

        PuzzleStreakStore.recordSolve(now: firstSolve, calendar: localCal, defaults: d)
        let streak = PuzzleStreakStore.recordSolve(now: secondSolve, calendar: localCal, defaults: d)

        // Using the injected local calendar, this is still the same day ->
        // no-op, rather than incrementing (which raw-UTC-day comparison
        // would incorrectly do).
        #expect(streak == 1)
        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 1)
    }

    @Test("reset clears persisted streak state")
    func resetClears() {
        let d = freshDefaults()
        let cal = utcCalendar
        PuzzleStreakStore.recordSolve(now: date(2026, 7, 1, calendar: cal), calendar: cal, defaults: d)

        PuzzleStreakStore.reset(defaults: d)

        #expect(PuzzleStreakStore.currentStreak(defaults: d) == 0)
        #expect(PuzzleStreakStore.lastSolvedDate(defaults: d) == nil)
    }
}
