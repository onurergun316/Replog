//
//  ProgressAnalyticsTests.swift
//  ReplogTests
//
//  The Progress dashboard's derivations: weekly buckets, muscle shares, rep-range mix,
//  adherence, PR events, and relative strength.
//

import Testing
import Foundation
@testable import Replog

struct ProgressAnalyticsTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: cal, year: y, month: m, day: d, hour: 12).date!
    }

    // 2026-06-10 is a Wednesday; its week starts Sunday 2026-06-07.
    private var today: Date { date(2026, 6, 10) }

    private func entry(_ day: Date, exId: String = "Bench",
                       sets: [RecordedSet], e1rm: Int = 100) -> HistoryEntry {
        HistoryEntry(exId: exId, date: day, topW: 100, topR: 5, e1rm: e1rm, sets: sets)
    }

    @Test func weekBucketsFillEmptyWeeksAndCountDistinctDays() {
        let history = [
            entry(date(2026, 6, 8), sets: [RecordedSet(w: 100, r: 10)]),        // this week Mon
            entry(date(2026, 6, 8), exId: "Row", sets: [RecordedSet(w: 50, r: 10)]), // same day
            entry(date(2026, 5, 25), sets: [RecordedSet(w: 80, r: 5)]),         // two weeks back
        ]
        let buckets = ProgressAnalytics.weekBuckets(history: history, weeks: 3,
                                                    today: today, calendar: cal)
        #expect(buckets.count == 3)
        #expect(buckets.map(\.volumeKg) == [400, 0, 1500])   // oldest → newest, gap week empty
        #expect(buckets.map(\.sets) == [1, 0, 2])
        #expect(buckets.last?.workouts == 1)                 // two entries, one training day
    }

    @Test func muscleSharesNormalizeAndSortLargestFirst() {
        let history = [
            entry(date(2026, 6, 8), exId: "Bench", sets: [RecordedSet(w: 100, r: 10)]),  // 1000 → chest
            entry(date(2026, 6, 9), exId: "Squat", sets: [RecordedSet(w: 100, r: 30)]),  // 3000 → quads
        ]
        let muscles: (String) -> [Muscle] = { $0 == "Bench" ? [.chest] : [.quadriceps] }
        let shares = ProgressAnalytics.muscleShares(history: history, days: 28,
                                                    muscles: muscles, today: today, calendar: cal)
        #expect(shares.map(\.muscle) == [.quadriceps, .chest])
        #expect(abs(shares[0].share - 0.75) < 0.001)
        #expect(abs(shares.map(\.share).reduce(0, +) - 1.0) < 0.001)
    }

    @Test func muscleSharesIgnoreEntriesOutsideTheWindowAndUnknownExercises() {
        let history = [
            entry(date(2026, 1, 1), exId: "Bench", sets: [RecordedSet(w: 100, r: 10)]),  // old
            entry(date(2026, 6, 9), exId: "Mystery", sets: [RecordedSet(w: 100, r: 10)]), // no muscles
        ]
        let shares = ProgressAnalytics.muscleShares(history: history, days: 28,
                                                    muscles: { $0 == "Bench" ? [.chest] : [] },
                                                    today: today, calendar: cal)
        #expect(shares.isEmpty)
    }

    @Test func repRangeMixBucketsSetsByReps() {
        let history = [entry(date(2026, 6, 8), sets: [
            RecordedSet(w: 100, r: 3), RecordedSet(w: 80, r: 8),
            RecordedSet(w: 80, r: 12), RecordedSet(w: 40, r: 20),
        ])]
        let mix = ProgressAnalytics.repRangeMix(history: history, days: 28,
                                                today: today, calendar: cal)
        #expect(mix.strength == 1)
        #expect(mix.hypertrophy == 2)
        #expect(mix.endurance == 1)
        #expect(mix.total == 4)
    }

    @Test func adherenceCountsOnlyElapsedScheduledDays() {
        let mwf: Set<Weekday> = [.mon, .wed, .fri]
        // Last week: all three done. This week (through Wed): Mon done, Wed not yet.
        let done = [date(2026, 6, 1), date(2026, 6, 3), date(2026, 6, 5), date(2026, 6, 8)]
        let weeks = ProgressAnalytics.adherence(scheduledDays: mwf, doneDates: done,
                                                weeks: 2, today: today, calendar: cal)
        #expect(weeks.count == 2)
        #expect(weeks[0].scheduled == 3 && weeks[0].done == 3)
        // Friday hasn't elapsed; Mon+Wed have (today is Wed), Mon done.
        #expect(weeks[1].scheduled == 2 && weeks[1].done == 1)
    }

    @Test func prEventsSkipTheBaselineAndFlagOnlyNewBests() {
        let history = [
            entry(date(2026, 5, 1), sets: [], e1rm: 100),   // baseline, not a PR
            entry(date(2026, 5, 8), sets: [], e1rm: 110),   // PR
            entry(date(2026, 5, 15), sets: [], e1rm: 105),  // below best — not a PR
            entry(date(2026, 5, 22), sets: [], e1rm: 120),  // PR
        ]
        let events = ProgressAnalytics.prEvents(history: history)
        #expect(events.map(\.e1rm) == [120, 110])            // newest first
    }

    @Test func relativeStrengthNeedsAPositiveBodyweight() {
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: 75) == 2.0)
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: nil) == nil)
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: 0) == nil)
    }
}
