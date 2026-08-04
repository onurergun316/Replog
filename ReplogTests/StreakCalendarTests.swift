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

    // MARK: - Paging through weeks

    @Test func aPastWeekStripShowsThatWeekAndNoToday() {
        // Today is Tue 30 June; one week back is Sun 21 … Sat 27 June.
        let strip = StreakCalendar.weekStrip(doneDates: [], weekOffset: -1,
                                             today: today, calendar: cal)
        #expect(strip.count == 7)
        #expect(strip.map(\.weekday) == [.sun, .mon, .tue, .wed, .thu, .fri, .sat])
        #expect(strip.allSatisfy { !$0.isToday })
        #expect(cal.component(.day, from: strip[0].date) == 21)
        #expect(cal.component(.day, from: strip[6].date) == 27)
    }

    @Test func aPastWeekMarksThatWeeksCompletions() {
        // Done on Mon 22 June (last week) and Mon 29 June (this week).
        let done = [day(22), day(29)]
        let lastWeek = StreakCalendar.weekStrip(doneDates: done, weekOffset: -1,
                                                today: today, calendar: cal)
        let thisWeek = StreakCalendar.weekStrip(doneDates: done, today: today, calendar: cal)

        #expect(lastWeek.filter(\.isCompleted).map(\.weekday) == [.mon])
        #expect(cal.component(.day, from: lastWeek.first { $0.isCompleted }!.date) == 22)
        #expect(thisWeek.filter(\.isCompleted).map(\.weekday) == [.mon])
        #expect(cal.component(.day, from: thisWeek.first { $0.isCompleted }!.date) == 29)
    }

    @Test func aFutureWeekIsReachableAndHasNothingCompleted() {
        let strip = StreakCalendar.weekStrip(doneDates: [day(29)], weekOffset: 1,
                                             today: today, calendar: cal)
        #expect(cal.component(.day, from: strip[0].date) == 5)   // Sun 5 July
        #expect(strip.allSatisfy { !$0.isCompleted })
        #expect(strip.allSatisfy { !$0.isToday })
    }

    @Test func theWindowIsAlwaysSwipeableEvenWithNoHistory() {
        let window = StreakCalendar.weekWindow(doneDates: [], today: today, calendar: cal)
        // A brand-new athlete can still swipe both ways rather than hitting a dead strip.
        #expect(window.lowerBound == -1)
        #expect(window.upperBound == 1)
    }

    @Test func theWindowReachesBackToTheEarliestTraining() {
        // Trained on 8 June, three weeks before the week of the 30th.
        let window = StreakCalendar.weekWindow(doneDates: [day(8), day(29)],
                                               today: today, calendar: cal)
        #expect(window.lowerBound == -3)
    }

    @Test func theWindowIsCappedSoThePagerStaysFinite() {
        let ancient = DateComponents(calendar: cal, year: 2015, month: 1, day: 5, hour: 12).date!
        let window = StreakCalendar.weekWindow(doneDates: [ancient], today: today,
                                               calendar: cal, maxWeeksBack: 52)
        #expect(window.lowerBound == -52)
    }

    @Test func weekLabelsReadAsPlainLanguageNearby() {
        #expect(StreakCalendar.weekLabel(offset: 0, today: today, calendar: cal) == "This week")
        #expect(StreakCalendar.weekLabel(offset: -1, today: today, calendar: cal) == "Last week")
        #expect(StreakCalendar.weekLabel(offset: 1, today: today, calendar: cal) == "Next week")
        // Further out, a date range is more use than "3 weeks ago".
        let far = StreakCalendar.weekLabel(offset: -3, today: today, calendar: cal)
        #expect(far.contains("–"))
        #expect(!far.isEmpty)
    }

    @Test func weekStartLandsOnSunday() {
        for offset in [-4, -1, 0, 2] {
            let start = StreakCalendar.weekStart(offset: offset, today: today, calendar: cal)!
            #expect(cal.component(.weekday, from: start) == 1)   // 1 = Sunday
        }
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
