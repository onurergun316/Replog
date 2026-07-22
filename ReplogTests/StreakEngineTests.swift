//
//  StreakEngineTests.swift
//  ReplogTests
//
//  Schedule-aware workout & week streaks: perfect weeks, missed scheduled days
//  breaking both streaks, in-progress grace, and multi-plan schedules.
//

import Testing
import Foundation
@testable import Replog

struct StreakEngineTests {

    // A fixed UTC Gregorian calendar so weekday math is deterministic.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// The Sunday that starts the week containing an arbitrary reference date.
    private func referenceSunday() -> Date {
        let comps = DateComponents(year: 2025, month: 6, day: 11) // a Wednesday
        let date = cal.date(from: comps)!
        return StreakEngine.startOfWeek(for: date, calendar: cal)!
    }

    /// `weeksBack` weeks before this week's Sunday, plus `weekdayOffset` days (Mon=1…).
    private func day(weeksBack: Int, _ weekdayOffset: Int) -> Date {
        let sunday = referenceSunday()
        return cal.date(byAdding: .day, value: -7 * weeksBack + weekdayOffset, to: sunday)!
    }

    private let mwf: Set<Weekday> = [.mon, .wed, .fri]
    private let mon = 1, wed = 3, fri = 5

    /// "Today" is this week's Wednesday.
    private var today: Date { day(weeksBack: 0, wed) }

    @Test func emptyHistoryIsZeroAndEmptyScheduleCountsPlainDays() {
        #expect(StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: [], today: today, calendar: cal) == 0)
        // Extras-only (no schedule): the streak is plain consecutive done days.
        #expect(StreakEngine.workoutStreak(scheduledDays: [], doneDates: [today], today: today, calendar: cal) == 1)
        let twoDays = [today, cal.date(byAdding: .day, value: -1, to: today)!]
        #expect(StreakEngine.workoutStreak(scheduledDays: [], doneDates: twoDays, today: today, calendar: cal) == 2)
        let gapped = [today, cal.date(byAdding: .day, value: -2, to: today)!]
        #expect(StreakEngine.workoutStreak(scheduledDays: [], doneDates: gapped, today: today, calendar: cal) == 1)
        // A perfect week needs a schedule; without one it stays 0.
        #expect(StreakEngine.weekStreak(scheduledDays: [], doneDates: [today], today: today, calendar: cal) == 0)
        #expect(StreakEngine.weekStreak(scheduledDays: mwf, doneDates: [], today: today, calendar: cal) == 0)
    }

    @Test func restDayCompletionCountsTowardTheStreak() {
        // Mon (scheduled) + Tue (rest day — an extra) + Wed (today) all done → 3, not 2.
        let done = [day(weeksBack: 0, mon), day(weeksBack: 0, 2), day(weeksBack: 0, wed)]
        let s = StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 3)
    }

    @Test func restDayCompletionDoesNotSaveAMissedScheduledDay() {
        // Monday (scheduled) skipped; Tuesday extra + today done → streak restarts at the miss.
        let done = [day(weeksBack: 0, 2), day(weeksBack: 0, wed)]
        let s = StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 2)
    }

    @Test func workoutStreakCountsConsecutiveScheduledSessions() {
        // Last week Mon/Wed/Fri done, this week Mon & Wed done (today = Wed, Fri not yet due).
        let done = [
            day(weeksBack: 1, mon), day(weeksBack: 1, wed), day(weeksBack: 1, fri),
            day(weeksBack: 0, mon), day(weeksBack: 0, wed),
        ]
        let s = StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 5)
    }

    @Test func missedPastScheduledDayBreaksWorkoutStreak() {
        // This week's Monday was skipped; only today's Wednesday is done.
        let done = [day(weeksBack: 0, wed)]
        let s = StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 1)
    }

    @Test func todaysUndoneWorkoutDoesNotBreakStreak() {
        // Today (Wed) not done yet, but Monday is — grace keeps the streak alive.
        let done = [day(weeksBack: 0, mon)]
        let s = StreakEngine.workoutStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 1)
    }

    @Test func weekStreakCountsPerfectWeeksPlusInProgress() {
        // Two perfect prior weeks; current week Mon+Wed done (in progress).
        let done = [
            day(weeksBack: 2, mon), day(weeksBack: 2, wed), day(weeksBack: 2, fri),
            day(weeksBack: 1, mon), day(weeksBack: 1, wed), day(weeksBack: 1, fri),
            day(weeksBack: 0, mon), day(weeksBack: 0, wed),
        ]
        let s = StreakEngine.weekStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 3) // 2 perfect weeks + current in-progress week
    }

    @Test func missThisWeekBreaksWeekStreakEvenWithPerfectPriorWeeks() {
        // Perfect prior week, but this week's Monday was missed.
        let done = [
            day(weeksBack: 1, mon), day(weeksBack: 1, wed), day(weeksBack: 1, fri),
            day(weeksBack: 0, wed), // Mon missed
        ]
        let s = StreakEngine.weekStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 0)
    }

    @Test func incompletePriorWeekStopsWeekStreak() {
        // Prior week missing Friday → not perfect → current in-progress week only.
        let done = [
            day(weeksBack: 1, mon), day(weeksBack: 1, wed), // no Friday
            day(weeksBack: 0, mon), day(weeksBack: 0, wed),
        ]
        let s = StreakEngine.weekStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 1)
    }

    @Test func todaysUndoneWorkoutDoesNotBreakWeekStreak() {
        // Today (Wed) not done; Monday done. Week streak still credits the in-progress week.
        let done = [
            day(weeksBack: 1, mon), day(weeksBack: 1, wed), day(weeksBack: 1, fri),
            day(weeksBack: 0, mon),
        ]
        let s = StreakEngine.weekStreak(scheduledDays: mwf, doneDates: done, today: today, calendar: cal)
        #expect(s == 2) // 1 perfect prior week + in-progress current week
    }

    @Test func scheduledDaysUnionsAcrossPlans() {
        let p1 = Plan(name: "A")
        let w1 = Workout(name: "Push", day: .mon); w1.plan = p1; p1.workouts = [w1]
        let p2 = Plan(name: "B")
        let w2 = Workout(name: "Pull", day: .thu); w2.plan = p2
        let w3 = Workout(name: "Legs", day: .mon); w3.plan = p2; p2.workouts = [w2, w3]
        let days = StreakEngine.scheduledDays(in: [p1, p2])
        #expect(days == [.mon, .thu])
    }
}
