//
//  StreakCalendarTests.swift
//  ReplogTests
//

import Testing
import Foundation
@testable import Replog

struct StreakCalendarTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Fixed reference date: 2026-06-30 (a Tuesday) at noon UTC.
    private var today: Date {
        DateComponents(calendar: cal, year: 2026, month: 6, day: 30, hour: 12).date!
    }

    private func day(_ d: Int) -> Date {
        DateComponents(calendar: cal, year: 2026, month: 6, day: d, hour: 12).date!
    }

    @Test func weekStripHasSevenDaysWithTodayMarked() {
        let strip = StreakCalendar.weekStrip(doneDates: [], today: today, calendar: cal)
        #expect(strip.count == 7)
        #expect(strip.map(\.weekday) == [.sun, .mon, .tue, .wed, .thu, .fri, .sat])
        let todays = strip.filter(\.isToday)
        #expect(todays.count == 1)
        #expect(todays.first?.weekday == .tue)
    }

    @Test func completedDaysAreColoredOnlyWhenDone() {
        // Completed Sunday (28th) and Monday (29th) of this week.
        let done = [day(28), day(29)]
        let strip = StreakCalendar.weekStrip(doneDates: done, today: today, calendar: cal)
        let completed = strip.filter(\.isCompleted).map(\.weekday)
        #expect(Set(completed) == [.sun, .mon])
        // Future days (Wed+) are never colored.
        #expect(strip.first { $0.weekday == .wed }?.isCompleted == false)
    }

    @Test func recordingCompletionIsIdempotentPerDay() {
        var dates: [Date] = []
        dates = StreakCalendar.recordingCompletion(today, into: dates, calendar: cal)
        dates = StreakCalendar.recordingCompletion(today, into: dates, calendar: cal) // same day twice
        #expect(dates.count == 1)
    }

    @Test func streakCountsConsecutiveDaysEndingToday() {
        // 28, 29, 30 done -> streak 3 (today is 30).
        let done = [day(28), day(29), day(30)]
        #expect(StreakCalendar.streak(doneDates: done, today: today, calendar: cal) == 3)
    }

    @Test func streakBreaksOnGap() {
        // 27 and 30 done, 28/29 missing -> streak today is just 1 (the 30th).
        let done = [day(27), day(30)]
        #expect(StreakCalendar.streak(doneDates: done, today: today, calendar: cal) == 1)
    }

    @Test func streakGracePeriodWhenTodayNotYetDone() {
        // Yesterday (29) done but not today -> streak still counts the run ending yesterday.
        let done = [day(28), day(29)]
        #expect(StreakCalendar.streak(doneDates: done, today: today, calendar: cal) == 2)
    }

    @Test func noStreakWhenNothingRecent() {
        let done = [day(20)]
        #expect(StreakCalendar.streak(doneDates: done, today: today, calendar: cal) == 0)
    }
}
