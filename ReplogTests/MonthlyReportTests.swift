//
//  MonthlyReportTests.swift
//  ReplogTests
//
//  The monthly rollup: exact stat math, e1RM movers, PR detection, month-boundary logic
//  (incl. year rollover), and once-per-month idempotence.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct MonthlyReportTests {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func entry(_ exId: String, _ date: Date, w: Double, r: Int, e1rm: Int) -> HistoryEntry {
        HistoryEntry(exId: exId, date: date, topW: w, topR: r, e1rm: e1rm,
                     sets: Array(repeating: RecordedSet(w: w, r: r), count: 3))
    }

    // MARK: - Stat math

    @Test func statMathIsExact() throws {
        let monthStart = date(2026, 6, 1)
        let history = [
            entry("X", date(2026, 6, 5), w: 100, r: 5, e1rm: 116),
            entry("X", date(2026, 6, 12), w: 100, r: 5, e1rm: 116),
        ]
        let report = try #require(MonthlyReportComposer.compose(
            monthStart: monthStart, history: history,
            doneDates: [date(2026, 6, 5), date(2026, 6, 12)],
            scheduledDays: [], coachingLogs: [], bodyweightEntries: [],
            goal: .buildMuscle, units: .kg, calendar: cal))

        #expect(report.stats.totalSets == 6)                 // 2 sessions × 3 sets
        #expect(report.stats.totalVolumeKg == 3000)          // 6 sets × 100 × 5
        #expect(report.stats.daysTrained == 2)
        #expect(report.markdown.contains("# Month in review"))
        #expect(report.markdown.contains("## Recommended adjustment"))
    }

    @Test func adherencePercentIsWholePercent() {
        #expect(MonthlyReportComposer.MonthStats(
            daysTrained: 6, scheduledCount: 8, scheduledDone: 6,
            totalSets: 0, totalVolumeKg: 0).adherencePct == 75)
        // Nothing scheduled → nil (the report shows a days-trained line instead).
        #expect(MonthlyReportComposer.MonthStats(
            daysTrained: 3, scheduledCount: 0, scheduledDone: 0,
            totalSets: 0, totalVolumeKg: 0).adherencePct == nil)
    }

    @Test func adherenceSurvivesCompositionCoherently() throws {
        // Schedule every weekday; train three days → adherence never exceeds 100 and is sane.
        let monthStart = date(2026, 6, 1)
        let history = [
            entry("X", date(2026, 6, 1), w: 80, r: 5, e1rm: 93),
            entry("X", date(2026, 6, 3), w: 80, r: 5, e1rm: 93),
            entry("X", date(2026, 6, 5), w: 80, r: 5, e1rm: 93),
        ]
        let report = try #require(MonthlyReportComposer.compose(
            monthStart: monthStart, history: history,
            doneDates: history.map(\.date),
            scheduledDays: Set(Weekday.allCases), coachingLogs: [], bodyweightEntries: [],
            goal: .buildMuscle, units: .kg, calendar: cal))
        let pct = try #require(report.stats.adherencePct)
        #expect(pct >= 0 && pct <= 100)
        #expect(report.stats.scheduledDone <= report.stats.scheduledCount)
    }

    // MARK: - e1RM movers

    @Test func topMoversRanksBiggestPositiveClimb() {
        let inMonth = [
            entry("X", date(2026, 6, 2), w: 100, r: 5, e1rm: 100),
            entry("X", date(2026, 6, 20), w: 105, r: 5, e1rm: 110),   // +10
            entry("Y", date(2026, 6, 2), w: 60, r: 8, e1rm: 76),
            entry("Y", date(2026, 6, 20), w: 62.5, r: 8, e1rm: 79),   // +3
            entry("Z", date(2026, 6, 2), w: 40, r: 5, e1rm: 46),      // single entry → no mover
            entry("D", date(2026, 6, 2), w: 50, r: 5, e1rm: 58),
            entry("D", date(2026, 6, 20), w: 45, r: 5, e1rm: 52),     // decreasing → excluded
        ]
        let movers = MonthlyReportComposer.topMovers(inMonth: inMonth)
        #expect(movers.map(\.exId) == ["X", "Y"])
        #expect(movers.first?.delta == 10)
        #expect(!movers.contains { $0.exId == "Z" || $0.exId == "D" })
    }

    // MARK: - PR detection through compose

    @Test func composeSurfacesNewRecordsAgainstPriorHistory() throws {
        let monthStart = date(2026, 6, 1)
        let history = [
            entry("X", date(2026, 5, 20), w: 100, r: 5, e1rm: 116),   // prior best (before month)
            entry("X", date(2026, 6, 10), w: 105, r: 5, e1rm: 122),   // new best in month
        ]
        let report = try #require(MonthlyReportComposer.compose(
            monthStart: monthStart, history: history,
            doneDates: [date(2026, 6, 10)],
            scheduledDays: [], coachingLogs: [], bodyweightEntries: [],
            goal: .buildMuscle, units: .kg, calendar: cal))
        #expect(report.records.contains { $0.exId == "X" && $0.value == 122 && $0.previousBest == 116 })
    }

    // MARK: - Boundary logic

    @Test func startOfMonthNormalisesToTheFirst() {
        #expect(MonthlyReportComposer.startOfMonth(for: date(2026, 6, 15), calendar: cal) == date(2026, 6, 1))
    }

    @Test func lastCompletedMonthIsThePriorMonth() {
        #expect(MonthlyReportComposer.lastCompletedMonthStart(now: date(2026, 2, 15), calendar: cal)
                == date(2026, 1, 1))
    }

    @Test func lastCompletedMonthRollsOverTheYear() {
        // January → the previous December of the prior year.
        #expect(MonthlyReportComposer.lastCompletedMonthStart(now: date(2026, 1, 10), calendar: cal)
                == date(2025, 12, 1))
    }

    // MARK: - Idempotence

    @Test func publishIfDueIsIdempotentPerMonth() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let now = date(2026, 7, 15)            // last completed month = June 2026
        context.insert(entry("X", date(2026, 6, 10), w: 100, r: 5, e1rm: 116))
        let profile = context.userProfile()
        profile.doneDates = [date(2026, 6, 10)]
        try context.save()

        let first = MonthlyReportComposer.publishIfDue(context: context, now: now, calendar: cal)
        #expect(first != nil)
        let second = MonthlyReportComposer.publishIfDue(context: context, now: now, calendar: cal)
        #expect(second == nil)                 // already published this month

        let reports = context.coachingLogs(kind: .monthlyReport)
        #expect(reports.count == 1)
    }

    @Test func idleMonthPublishesNoReport() {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let now = date(2026, 7, 15)
        // No history, no done dates → nothing to report.
        #expect(MonthlyReportComposer.publishIfDue(context: context, now: now, calendar: cal) == nil)
    }
}
