//
//  WeeklyReportTests.swift
//  ReplogTests
//
//  The weekly report (D1): pure composition (stats, records, coaching note, markdown)
//  against fixed fixtures, and the once-per-week publish path into the coaching memory.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct WeeklyReportTests {

    private let calendar = Calendar.current

    /// A fixed "now": Wednesday, 2026-07-01 (noon, local).
    private var now: Date { date(2026, 7, 1) }
    /// The most recently completed week for `now` (Sunday-start, per StreakEngine).
    private var weekStart: Date {
        WeeklyReportComposer.lastCompletedWeekStart(now: now, calendar: calendar)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    /// `days` after the start of the reported week, at noon.
    private func inWeek(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: weekStart)!.addingTimeInterval(12 * 3600)
    }

    private func entry(_ exId: String, _ date: Date, w: Double, r: Int,
                       sets: [RecordedSet]? = nil) -> HistoryEntry {
        HistoryEntry(exId: exId, date: date, topW: w, topR: r,
                     e1rm: Formulas.e1rmRounded(kg: w, reps: r),
                     sets: sets ?? [RecordedSet(w: w, r: r)])
    }

    private func compose(
        history: [HistoryEntry] = [],
        doneDates: [Date] = [],
        scheduledDays: Set<Weekday> = [],
        coachingLogs: [CoachingLog] = [],
        bodyweightEntries: [BodyweightEntry] = [],
        goal: Goal = .buildMuscle,
        units: Units = .kg
    ) -> WeeklyReportComposer.Report? {
        WeeklyReportComposer.compose(
            weekStart: weekStart, history: history, doneDates: doneDates,
            scheduledDays: scheduledDays, coachingLogs: coachingLogs,
            bodyweightEntries: bodyweightEntries, goal: goal, units: units,
            calendar: calendar)
    }

    // MARK: - Composition guards & stats

    @Test func idleWeekComposesNil() {
        // Activity outside the week doesn't count.
        let history = [entry("Squat", inWeek(-3), w: 100, r: 5),
                       entry("Squat", inWeek(9), w: 100, r: 5)]
        #expect(compose(history: history) == nil)
        #expect(compose() == nil)
    }

    @Test func statsCountSetsVolumeAndDays() throws {
        let history = [
            entry("Barbell_Bench_Press", inWeek(1), w: 80, r: 8,
                  sets: [RecordedSet(w: 80, r: 8), RecordedSet(w: 70, r: 10)]),
            entry("Barbell_Squat", inWeek(3), w: 100, r: 5,
                  sets: [RecordedSet(w: 100, r: 5)]),
        ]
        let report = try #require(compose(history: history))
        #expect(report.stats.daysTrained == 2)
        #expect(report.stats.totalSets == 3)
        let expectedVolume = Double(80 * 8 + 70 * 10 + 100 * 5)
        #expect(report.stats.totalVolumeKg == expectedVolume)
        #expect(report.stats.previousWeekSets == nil)
        #expect(report.headline.hasPrefix("Week in review"))
    }

    @Test func doneDateAloneCountsAsTrainingDay() throws {
        // A finished workout with no logged sets still shows up in adherence.
        let report = try #require(compose(doneDates: [inWeek(2)]))
        #expect(report.stats.daysTrained == 1)
        #expect(report.stats.totalSets == 0)
    }

    @Test func weekBoundariesAreStartInclusiveEndExclusive() throws {
        let atStart = entry("Squat", weekStart, w: 100, r: 5)
        let atEnd = entry("Squat", calendar.date(byAdding: .day, value: 7, to: weekStart)!,
                          w: 120, r: 5)
        let report = try #require(compose(history: [atStart, atEnd]))
        #expect(report.stats.totalSets == 1)
        #expect(report.stats.totalVolumeKg == 500)
    }

    @Test func adherenceCountsScheduledDaysOnly() throws {
        // Week runs Sun..Sat. Trained the Monday (scheduled) and Tuesday (not scheduled),
        // missed Wednesday + Friday.
        let scheduled: Set<Weekday> = [.mon, .wed, .fri]
        let report = try #require(compose(
            doneDates: [inWeek(1), inWeek(2)], scheduledDays: scheduled))
        #expect(report.stats.daysScheduled == 3)
        #expect(report.stats.scheduledDone == 1)
        #expect(report.stats.daysTrained == 2)
        #expect(report.stats.extraDays == 1)
        #expect(report.stats.isPerfectWeek == false)
        #expect(report.markdown.contains("**1 of 3** scheduled workouts completed"))
        #expect(report.markdown.contains("+1 extra session"))
    }

    @Test func perfectWeekIsCalledOut() throws {
        let report = try #require(compose(
            doneDates: [inWeek(1), inWeek(3), inWeek(5)],
            scheduledDays: [.mon, .wed, .fri]))
        #expect(report.stats.isPerfectWeek)
        #expect(report.markdown.contains("**3 of 3** scheduled workouts completed — a perfect week"))
    }

    @Test func noScheduleFallsBackToDaysLoggedLine() throws {
        let report = try #require(compose(history: [entry("Squat", inWeek(1), w: 100, r: 5)]))
        #expect(report.markdown.contains("**1** training day logged"))
        #expect(!report.markdown.contains("scheduled workouts"))
    }

    @Test func previousWeekSetsComparisonAppears() throws {
        let history = [
            entry("Squat", inWeek(-3), w: 95, r: 5,
                  sets: [RecordedSet(w: 95, r: 5), RecordedSet(w: 90, r: 5)]),
            entry("Squat", inWeek(2), w: 100, r: 5),
        ]
        let report = try #require(compose(history: history))
        #expect(report.stats.previousWeekSets == 2)
        #expect(report.markdown.contains("(last week: 2 sets)"))
    }

    // MARK: - Records

    @Test func e1rmRecordBeatsPriorBest() throws {
        let history = [
            entry("Barbell_Bench_Press", inWeek(-10), w: 75, r: 8), // e1rm 95
            entry("Barbell_Bench_Press", inWeek(2), w: 80, r: 8),   // e1rm 101
        ]
        let report = try #require(compose(history: history))
        #expect(report.records == [WeeklyReportComposer.PersonalRecord(
            exId: "Barbell_Bench_Press", value: 101, previousBest: 95, isRepRecord: false)])
        #expect(report.markdown.contains("**Barbell Bench Press** — est. 1RM 101, up from 95"))
    }

    @Test func noRecordWhenPriorBestStands() throws {
        let history = [
            entry("Squat", inWeek(-10), w: 120, r: 8),
            entry("Squat", inWeek(2), w: 100, r: 8),
        ]
        let report = try #require(compose(history: history))
        #expect(report.records.isEmpty)
        #expect(!report.markdown.contains("New records"))
    }

    @Test func firstEverLiftIsNotARecord() throws {
        let report = try #require(compose(history: [entry("Deadlift", inWeek(1), w: 140, r: 5)]))
        #expect(report.records.isEmpty)
    }

    @Test func bodyweightLiftRecordsOnReps() throws {
        let history = [
            entry("Pullups", inWeek(-10), w: 0, r: 8),
            entry("Pullups", inWeek(2), w: 0, r: 10),
        ]
        let report = try #require(compose(history: history))
        #expect(report.records == [WeeklyReportComposer.PersonalRecord(
            exId: "Pullups", value: 10, previousBest: 8, isRepRecord: true)])
        #expect(report.markdown.contains("**Pullups** — 10 reps, up from 8"))
    }

    @Test func recordsSortByImprovementAndCap() throws {
        var history: [HistoryEntry] = []
        for i in 0..<7 {
            let exId = "Lift_\(i)"
            history.append(entry(exId, inWeek(-10), w: 50, r: 5))            // baseline e1rm ~58
            history.append(entry(exId, inWeek(2), w: 50 + Double(i + 1) * 2.5, r: 5))
        }
        let report = try #require(compose(history: history))
        #expect(report.records.count == WeeklyReportComposer.maxRecords)
        // Biggest jump (Lift_6) leads; improvements strictly decrease down the list.
        #expect(report.records.first?.exId == "Lift_6")
        let improvements = report.records.map { $0.value - $0.previousBest }
        #expect(improvements == improvements.sorted(by: >))
    }

    // MARK: - Coaching note priorities

    @Test func inWeekStallNoteWinsOverRecords() throws {
        let stall = CoachingLog(kind: .deload, summary: "Bench has stalled — deload to 72.5kg.",
                                date: inWeek(3), exId: "Barbell_Bench_Press")
        let outside = CoachingLog(kind: .plateau, summary: "Old news", date: inWeek(-9))
        let history = [
            entry("Squat", inWeek(-10), w: 100, r: 5),
            entry("Squat", inWeek(2), w: 110, r: 5), // would otherwise be the record note
        ]
        let report = try #require(compose(history: history, coachingLogs: [outside, stall]))
        #expect(report.markdown.contains("Bench has stalled — deload to 72.5kg."))
        #expect(!report.markdown.contains("Old news"))
    }

    @Test func recordNoteWhenNoStall() throws {
        let history = [
            entry("Squat", inWeek(-10), w: 100, r: 5),
            entry("Squat", inWeek(2), w: 110, r: 5),
        ]
        let report = try #require(compose(history: history))
        #expect(report.markdown.contains("new personal best on Squat"))
    }

    @Test func trendingNoteWhenNoRecordOrStall() throws {
        // Old peak stays unbeaten, but the last two sessions trend up → note #3.
        let history = [
            entry("Squat", inWeek(-20), w: 130, r: 5), // old best, e1rm 152
            entry("Squat", inWeek(-6), w: 100, r: 5),  // e1rm 117
            entry("Squat", inWeek(2), w: 105, r: 5),   // e1rm 123 — up vs last, below best
        ]
        let report = try #require(compose(history: history))
        #expect(report.records.isEmpty)
        #expect(report.markdown.contains("Squat is trending up"))
    }

    @Test func adherenceNoteAsLastResort() throws {
        let flat = [entry("Squat", inWeek(-6), w: 100, r: 5),
                    entry("Squat", inWeek(2), w: 100, r: 5)]
        let partial = try #require(compose(history: flat, scheduledDays: [.mon, .wed, .fri]))
        #expect(partial.markdown.contains("Consistency beats intensity"))

        let perfectDays = [inWeek(1), inWeek(3), inWeek(5)]
        let perfect = try #require(compose(history: flat, doneDates: perfectDays,
                                           scheduledDays: [.mon, .wed, .fri]))
        #expect(perfect.markdown.contains("A perfect week of showing up"))
    }

    // MARK: - Bodyweight section & units

    @Test func bodyweightSectionUsesEntriesUpToWeekEnd() throws {
        let entries = [BodyweightEntry(weightKg: 80.0, date: inWeek(-12)),
                       BodyweightEntry(weightKg: 79.0, date: inWeek(-5)),
                       BodyweightEntry(weightKg: 78.2, date: inWeek(4)),
                       BodyweightEntry(weightKg: 60.0, date: inWeek(9))] // after the week: ignored
        let report = try #require(compose(history: [entry("Squat", inWeek(1), w: 100, r: 5)],
                                          bodyweightEntries: entries))
        #expect(report.markdown.contains("## Bodyweight"))
        #expect(report.markdown.contains("**78.2kg**"))
        #expect(report.markdown.contains("trending down"))
    }

    @Test func bodyweightSectionOmittedWithoutEntries() throws {
        let report = try #require(compose(history: [entry("Squat", inWeek(1), w: 100, r: 5)]))
        #expect(!report.markdown.contains("## Bodyweight"))
    }

    @Test func volumeRendersInDisplayUnits() throws {
        let history = [entry("Squat", inWeek(1), w: 100, r: 10)] // 1000 kg ≈ 2205 lb
        let kg = try #require(compose(history: history, units: .kg))
        #expect(kg.markdown.contains("**1,000kg** total volume"))
        let lb = try #require(compose(history: history, units: .lb))
        #expect(lb.markdown.contains("**2,205lb** total volume"))
    }

    @Test func encouragementMatchesGoal() throws {
        let history = [entry("Squat", inWeek(1), w: 100, r: 5)]
        let cut = try #require(compose(history: history, goal: .loseWeight))
        #expect(cut.markdown.contains("> The scale follows the work"))
        let sport = try #require(compose(history: history, goal: .sport))
        #expect(sport.markdown.contains("> Strong athletes are durable athletes"))
    }

    // MARK: - Publishing

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    @Test func lastCompletedWeekStartIsPreviousWeek() throws {
        let start = try #require(WeeklyReportComposer.lastCompletedWeekStart(
            now: now, calendar: calendar))
        let thisWeek = try #require(StreakEngine.startOfWeek(for: now, calendar: calendar))
        #expect(calendar.dateComponents([.day], from: start, to: thisWeek).day == 7)
        #expect(start == calendar.startOfDay(for: start))
    }

    @Test func publishRecordsOnceAndIsIdempotent() throws {
        let ctx = makeContext()
        ctx.insert(entry("Barbell_Bench_Press", inWeek(-10), w: 75, r: 8))
        ctx.insert(entry("Barbell_Bench_Press", inWeek(2), w: 80, r: 8))
        try ctx.save()

        let published = try #require(WeeklyReportComposer.publishIfDue(
            context: ctx, now: now, calendar: calendar))
        #expect(published.kind == .weeklyReport)
        #expect(published.summary.hasPrefix("Week in review"))
        #expect(published.bodyMarkdown?.contains("est. 1RM 101, up from 95") == true)
        let storedStart = try #require(
            published.payload[metric: WeeklyReportComposer.MetricKey.weekStart])
        #expect(abs(storedStart - weekStart.timeIntervalSinceReferenceDate) < 1)
        #expect(published.payload[metric: WeeklyReportComposer.MetricKey.sets] == 1)

        // Second call (e.g. next app open, same week) is a no-op.
        #expect(WeeklyReportComposer.publishIfDue(context: ctx, now: now, calendar: calendar) == nil)
        #expect(ctx.coachingLogs(kind: .weeklyReport).count == 1)
    }

    @Test func publishSkipsIdleWeek() throws {
        let ctx = makeContext()
        ctx.insert(entry("Squat", inWeek(-10), w: 100, r: 5)) // older week only
        try ctx.save()
        #expect(WeeklyReportComposer.publishIfDue(context: ctx, now: now, calendar: calendar) == nil)
        #expect(ctx.coachingLogs(kind: .weeklyReport).isEmpty)
    }

    @Test func publishAgainForANewWeek() throws {
        let ctx = makeContext()
        ctx.insert(entry("Squat", inWeek(2), w: 100, r: 5))
        ctx.insert(entry("Squat", inWeek(9), w: 102.5, r: 5))
        try ctx.save()

        #expect(WeeklyReportComposer.publishIfDue(context: ctx, now: now, calendar: calendar) != nil)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        #expect(WeeklyReportComposer.publishIfDue(context: ctx, now: nextWeek, calendar: calendar) != nil)
        #expect(ctx.coachingLogs(kind: .weeklyReport).count == 2)
    }

    @Test func bodyMarkdownPersistsAcrossContexts() throws {
        let container = ReplogSchema.inMemoryContainer()
        let ctx = ModelContext(container)
        ctx.recordCoaching(.weeklyReport, summary: "Week in review · test",
                           bodyMarkdown: "# Week in review\nBody.")
        try ctx.save()

        let fresh = ModelContext(container)
        let logs = fresh.coachingLogs(kind: .weeklyReport)
        #expect(logs.count == 1)
        #expect(logs.first?.bodyMarkdown == "# Week in review\nBody.")
        // Non-report memories keep a nil body.
        #expect(CoachingLog(kind: .note, summary: "x").bodyMarkdown == nil)
    }
}
