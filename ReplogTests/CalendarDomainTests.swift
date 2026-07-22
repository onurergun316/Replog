//
//  CalendarDomainTests.swift
//  ReplogTests
//
//  The Calendar tab's pure logic: 42-cell Sunday-first month grids, done-day derivation,
//  day-detail entries, and range totals/averages over selected days.
//

import Testing
import Foundation
@testable import Replog

struct CalendarDomainTests {

    // A fixed UTC Gregorian, Sunday-first — deterministic regardless of machine locale.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return CalendarMath.gridCalendar(c)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: cal, year: y, month: m, day: d, hour: 12).date!
    }

    // MARK: Grid math

    @Test func monthPageIsAlways42SundayFirstCells() {
        // June 2026 starts on a Monday → one leading May day (Sunday the 31st).
        let cells = CalendarMath.monthCells(containing: date(2026, 6, 15), calendar: cal)
        #expect(cells.count == 42)
        #expect(cal.component(.weekday, from: cells.first!) == 1) // Sunday column first
        #expect(cal.isDate(cells.first!, inSameDayAs: date(2026, 5, 31)))
        #expect(cells.contains { cal.isDate($0, inSameDayAs: date(2026, 6, 1)) })
        #expect(cells.contains { cal.isDate($0, inSameDayAs: date(2026, 6, 30)) })
    }

    @Test func monthStartingOnSundayHasNoLeadingDays() {
        // February 2026 starts on a Sunday; 42 cells still pad out with March.
        let cells = CalendarMath.monthCells(containing: date(2026, 2, 10), calendar: cal)
        #expect(cal.isDate(cells.first!, inSameDayAs: date(2026, 2, 1)))
        #expect(cells.count == 42)
        #expect(cal.isDate(cells.last!, inSameDayAs: date(2026, 3, 14)))
    }

    @Test func inMonthAndMonthSteppingWork() {
        let june = date(2026, 6, 15)
        #expect(CalendarMath.isInMonth(date(2026, 6, 1), of: june, calendar: cal))
        #expect(!CalendarMath.isInMonth(date(2026, 5, 31), of: june, calendar: cal))
        let july = CalendarMath.month(1, from: june, calendar: cal)!
        #expect(cal.component(.month, from: july) == 7)
        #expect(cal.component(.day, from: july) == 1)
    }

    // MARK: Stats

    private func entry(_ day: Date, exId: String = "Bench",
                       sets: [RecordedSet], topW: Double, topR: Int) -> HistoryEntry {
        HistoryEntry(exId: exId, date: day, topW: topW, topR: topR,
                     e1rm: Formulas.e1rmRounded(kg: topW, reps: topR), sets: sets)
    }

    @Test func doneDaysUnionsCalendarAndHistory() {
        let markedOnly = date(2026, 6, 1)
        let historyOnly = date(2026, 6, 3)
        let days = CalendarStats.doneDays(
            doneDates: [markedOnly],
            history: [entry(historyOnly, sets: [RecordedSet(w: 60, r: 10)], topW: 60, topR: 10)],
            calendar: cal)
        #expect(days.contains(cal.startOfDay(for: markedOnly)))
        #expect(days.contains(cal.startOfDay(for: historyOnly)))
        #expect(days.count == 2)
    }

    @Test func dayEntriesAreHeaviestFirst() {
        let day = date(2026, 6, 2)
        let light = entry(day, exId: "Curl", sets: [RecordedSet(w: 20, r: 10)], topW: 20, topR: 10)
        let heavy = entry(day, exId: "Squat", sets: [RecordedSet(w: 100, r: 5)], topW: 100, topR: 5)
        let other = entry(date(2026, 6, 3), exId: "Row", sets: [RecordedSet(w: 50, r: 8)], topW: 50, topR: 8)
        let entries = CalendarStats.entries(on: day, history: [light, other, heavy], calendar: cal)
        #expect(entries.map(\.exId) == ["Squat", "Curl"])
    }

    @Test func rangeSummaryTotalsAndAverages() {
        let d1 = date(2026, 6, 1), d2 = date(2026, 6, 2), d3 = date(2026, 6, 3)
        let history = [
            entry(d1, exId: "Bench", sets: [RecordedSet(w: 60, r: 10), RecordedSet(w: 60, r: 8)],
                  topW: 60, topR: 10),
            entry(d2, exId: "Squat", sets: [RecordedSet(w: 100, r: 5)], topW: 100, topR: 5),
        ]
        // d3 selected but empty; d2 also marked done in the calendar (binary day).
        let s = CalendarStats.summary(selection: [d1, d2, d3], doneDates: [d2],
                                      history: history, calendar: cal)
        #expect(s.selectedDays == 3)
        #expect(s.trainingDays == 2)
        #expect(s.totalSets == 3)
        #expect(s.totalReps == 23)
        let expectedVolume: Double = 600 + 480 + 500   // 60×10 + 60×8 + 100×5
        #expect(s.totalVolumeKg == expectedVolume)
        #expect(s.distinctExercises == 2)
        #expect(s.bestLift == BestLift(exId: "Squat", weightKg: 100, reps: 5,
                                       e1rm: Formulas.e1rmRounded(kg: 100, reps: 5)))
        #expect(abs(s.avgSetsPerTrainingDay - 1.5) < 0.001)
        #expect(abs(s.avgVolumePerTrainingDay - (1580.0 / 2)) < 0.001)
    }

    @Test func dayTotalsAggregatePerDayAcrossEntries() {
        let day = date(2026, 6, 2)
        let history = [
            entry(day, exId: "Bench", sets: [RecordedSet(w: 60, r: 10)], topW: 60, topR: 10),
            entry(day, exId: "Row", sets: [RecordedSet(w: 50, r: 8), RecordedSet(w: 50, r: 8)],
                  topW: 50, topR: 8),
        ]
        let totals = CalendarStats.dayTotals(history: history, calendar: cal)
        let t = totals[cal.startOfDay(for: day)]
        #expect(t?.sets == 3)
        #expect(t?.reps == 26)
        let expectedVolume: Double = 600 + 400 + 400
        #expect(t?.volumeKg == expectedVolume)
        #expect(totals.count == 1)
    }

    @Test func emptySelectionIsAllZeros() {
        let s = CalendarStats.summary(selection: [], doneDates: [date(2026, 6, 1)],
                                      history: [], calendar: cal)
        #expect(s == RangeSummary())
        #expect(s.avgSetsPerTrainingDay == 0)
    }

    @Test func monthTotalsStayInsideTheMonth() {
        let inJune = entry(date(2026, 6, 10), sets: [RecordedSet(w: 50, r: 10)], topW: 50, topR: 10)
        let inMay = entry(date(2026, 5, 30), sets: [RecordedSet(w: 90, r: 10)], topW: 90, topR: 10)
        let totals = CalendarStats.monthTotals(month: date(2026, 6, 15),
                                               doneDates: [date(2026, 6, 20)],
                                               history: [inJune, inMay], calendar: cal)
        #expect(totals.workouts == 2)      // the 10th (history) + the 20th (marked)
        #expect(totals.volumeKg == 500)    // May volume excluded
    }

    @Test func firstOfNextMonthNeverLeaksIntoThisMonth() {
        // A month interval's exclusive end == the next month's first instant, which is
        // exactly where a start-of-day done mark for the 1st lands — the trailing edge.
        let july1 = cal.startOfDay(for: date(2026, 7, 1))
        let totals = CalendarStats.monthTotals(
            month: date(2026, 6, 15),
            doneDates: [july1],
            history: [entry(july1, sets: [RecordedSet(w: 80, r: 5)], topW: 80, topR: 5)],
            calendar: cal)
        #expect(totals.workouts == 0)
        #expect(totals.volumeKg == 0)
    }
}
