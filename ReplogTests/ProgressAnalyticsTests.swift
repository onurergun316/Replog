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

@MainActor
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
                       sets: [RecordedSet], e1rm: Int = 100,
                       sessionId: UUID? = nil, workoutName: String? = nil,
                       planName: String? = nil) -> HistoryEntry {
        HistoryEntry(exId: exId, date: day, topW: 100, topR: 5, e1rm: e1rm, sets: sets,
                     sessionId: sessionId, workoutName: workoutName, planName: planName)
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

    // MARK: - X-domain: where the series starts

    @Test func leadingEmptyWeeksAreTrimmedSoFirstTrainingReadsAtTheLeft() {
        // A new athlete who started this week: the raw window pads 11 weeks of nothing
        // in front of them, which put their only bar at the chart's far right edge.
        let history = [entry(date(2026, 6, 8), sets: [RecordedSet(w: 100, r: 10)])]
        let raw = ProgressAnalytics.weekBuckets(history: history, weeks: 12,
                                                today: today, calendar: cal)
        #expect(raw.count == 12)
        #expect(raw.first?.sets == 0)

        let trimmed = ProgressAnalytics.trimmingLeadingEmptyWeeks(raw)
        #expect(trimmed.count == 1)
        #expect(trimmed.first?.volumeKg == 1000)
    }

    @Test func trimmingKeepsInteriorAndTrailingGaps() {
        // A week you skipped is information; the current week must stay the right edge.
        let history = [
            entry(date(2026, 5, 25), sets: [RecordedSet(w: 80, r: 5)]),   // two weeks back
        ]
        let buckets = ProgressAnalytics.trimmingLeadingEmptyWeeks(
            ProgressAnalytics.weekBuckets(history: history, weeks: 4, today: today, calendar: cal))

        #expect(buckets.count == 3)                       // one leading empty week dropped
        #expect(buckets.map(\.sets) == [1, 0, 0])         // the gap and this week survive
    }

    @Test func trimmingCountsABodyweightOnlyWeekAsTrained() {
        // Zero kilograms under the default resolver, but unquestionably a training week —
        // keying the trim on volume would delete it.
        let history = [entry(date(2026, 6, 8), sets: [RecordedSet(w: 0, r: 20)])]
        let buckets = ProgressAnalytics.trimmingLeadingEmptyWeeks(
            ProgressAnalytics.weekBuckets(history: history, weeks: 6, today: today, calendar: cal))

        #expect(buckets.count == 1)
        #expect(buckets.first?.volumeKg == 0)
        #expect(buckets.first?.sets == 1)
    }

    @Test func trimmingAnEmptyHistoryLeavesTheWindowAlone() {
        let buckets = ProgressAnalytics.weekBuckets(history: [], weeks: 4,
                                                    today: today, calendar: cal)
        #expect(ProgressAnalytics.trimmingLeadingEmptyWeeks(buckets).count == 4)
    }

    @Test func adherenceIgnoresWeeksBeforeTheAthleteStarted() {
        // Started this week, trains Mondays, did Monday. Without the clamp the previous
        // 11 weeks count as missed sessions against a schedule that did not exist yet.
        let started = date(2026, 6, 8)
        let unclamped = ProgressAnalytics.adherence(scheduledDays: [.mon], doneDates: [started],
                                                    weeks: 12, today: today, calendar: cal)
        #expect(unclamped.count == 12)
        #expect(unclamped.reduce(0) { $0 + $1.scheduled } == 12)
        #expect(unclamped.reduce(0) { $0 + $1.done } == 1)      // reads as 8% adherence

        let clamped = ProgressAnalytics.adherence(scheduledDays: [.mon], doneDates: [started],
                                                  weeks: 12, since: started,
                                                  today: today, calendar: cal)
        #expect(clamped.count == 1)
        #expect(clamped.first?.scheduled == 1)
        #expect(clamped.first?.done == 1)                       // 100%, which is the truth
    }

    @Test func firstActivityIsTheEarliestOfHistoryAndCompletedDays() {
        let history = [entry(date(2026, 6, 8), sets: [RecordedSet(w: 100, r: 5)])]
        #expect(ProgressAnalytics.firstActivity(history: history,
                                                doneDates: [date(2026, 6, 1)]) == date(2026, 6, 1))
        #expect(ProgressAnalytics.firstActivity(history: history, doneDates: []) == date(2026, 6, 8))
        #expect(ProgressAnalytics.firstActivity(history: [], doneDates: []) == nil)
    }

    // MARK: - Sessions

    @Test func twoWorkoutsInOneDayStayTwoSessions() {
        // History is per-exercise-per-day, so a morning and an evening session used to
        // merge. SessionFinisher stamps one id per finish, which keeps them apart.
        let morning = UUID(), evening = UUID()
        let day = date(2026, 6, 8)
        let history = [
            entry(day, exId: "Bench", sets: [RecordedSet(w: 100, r: 5)], sessionId: morning),
            entry(day, exId: "Row", sets: [RecordedSet(w: 60, r: 10)], sessionId: morning),
            entry(day.addingTimeInterval(36_000), exId: "Squat",
                  sets: [RecordedSet(w: 120, r: 5)], sessionId: evening),
        ]

        let sessions = ProgressAnalytics.sessions(history: history)
        #expect(sessions.count == 2)
        #expect(sessions[0].entries.count == 2)     // oldest first
        #expect(sessions[1].entries.count == 1)
    }

    @Test func sessionsWrittenBeforeAttributionGroupByTimestamp() {
        // Legacy rows have no sessionId; one finish still shares one exact timestamp.
        let stamp = date(2026, 6, 8)
        let history = [
            entry(stamp, exId: "Bench", sets: [RecordedSet(w: 100, r: 5)]),
            entry(stamp, exId: "Row", sets: [RecordedSet(w: 60, r: 10)]),
        ]
        let sessions = ProgressAnalytics.sessions(history: history)
        #expect(sessions.count == 1)
        #expect(sessions[0].entries.count == 2)
        #expect(sessions[0].workoutName == nil)
    }

    @Test func sessionTonnageSumsItsExercises() {
        let day = date(2026, 6, 8)
        let history = [
            entry(day, exId: "Bench", sets: [RecordedSet(w: 100, r: 5)], sessionId: UUID()),
        ]
        let session = ProgressAnalytics.sessions(history: history)[0]
        #expect(ProgressAnalytics.tonnage(of: session) == 500)
    }

    @Test func tonnageGroupsByPlanAndWorkout() {
        let day = date(2026, 6, 8)
        let history = [
            entry(day, exId: "Bench", sets: [RecordedSet(w: 100, r: 5)],
                  sessionId: UUID(), workoutName: "Push", planName: "PPL"),
            entry(day.addingTimeInterval(3600), exId: "Squat", sets: [RecordedSet(w: 100, r: 10)],
                  sessionId: UUID(), workoutName: "Legs", planName: "PPL"),
            entry(day.addingTimeInterval(7200), exId: "Row", sets: [RecordedSet(w: 50, r: 4)],
                  sessionId: UUID()),                       // unattributed legacy row
        ]

        let byPlan = ProgressAnalytics.tonnageByPlan(history: history)
        #expect(byPlan.first?.plan == "PPL")
        #expect(byPlan.first?.volumeKg == 1500)             // 500 + 1000, largest first
        #expect(byPlan.contains { $0.plan == nil && $0.volumeKg == 200 })

        let byWorkout = ProgressAnalytics.tonnageByWorkout(history: history)
        #expect(byWorkout.first?.workout == "Legs")          // 1000 outranks Push's 500
    }

    @Test func muscleSetsCountHardSetsAndRankThem() {
        // Sets, not kilograms: tonnage makes a leg-press day look heroic and a strict
        // overhead-press day look like nothing, which is the wrong unit for balance.
        let history = [
            entry(date(2026, 6, 8), exId: "Bench",
                  sets: [RecordedSet(w: 100, r: 10), RecordedSet(w: 100, r: 10)]),
            entry(date(2026, 6, 9), exId: "Squat", sets: [RecordedSet(w: 20, r: 30)]),
        ]
        let muscles: (String) -> [Muscle] = { $0 == "Bench" ? [.chest] : [.quadriceps] }

        let ranked = ProgressAnalytics.muscleSets(history: history, days: 30,
                                                  muscles: muscles, today: today, calendar: cal)
        #expect(ranked.map(\.muscle) == [.chest, .quadriceps])   // 2 sets beats 1...
        #expect(ranked.map(\.sets) == [2, 1])
        // ...even though the squat moved more total weight (600 kg vs 2000 kg is not
        // the question a balance chart asks).
    }

    @Test func muscleSetsCountABodyweightSessionTheSameAsALoadedOne() {
        // A set is a set: this is why balance is counted in sets and needs no resolver.
        let history = [entry(date(2026, 6, 8), exId: "Pushups",
                             sets: [RecordedSet(w: 0, r: 20), RecordedSet(w: 0, r: 20)])]
        let ranked = ProgressAnalytics.muscleSets(history: history, days: 30,
                                                  muscles: { _ in [.chest] },
                                                  today: today, calendar: cal)
        #expect(ranked.map(\.muscle) == [.chest])
        #expect(ranked.map(\.sets) == [2])
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
        // Keyed on the top set: PRs are recomputed over effective load so a bodyweight
        // lift can set one, which means the stored `e1rm` field is no longer read.
        func session(_ day: Date, topW: Double) -> HistoryEntry {
            HistoryEntry(exId: "Bench", date: day, topW: topW, topR: 5,
                         e1rm: Formulas.e1rmRounded(kg: topW, reps: 5), sets: [])
        }
        let history = [
            session(date(2026, 5, 1), topW: 100),    // baseline, not a PR
            session(date(2026, 5, 8), topW: 110),    // PR
            session(date(2026, 5, 15), topW: 105),   // below best — not a PR
            session(date(2026, 5, 22), topW: 120),   // PR
        ]
        let events = ProgressAnalytics.prEvents(history: history)
        #expect(events.map(\.e1rm) == [Formulas.e1rmRounded(kg: 120, reps: 5),
                                       Formulas.e1rmRounded(kg: 110, reps: 5)])  // newest first
    }

    @Test func relativeStrengthNeedsAPositiveBodyweight() {
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: 75) == 2.0)
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: nil) == nil)
        #expect(ProgressAnalytics.relativeStrength(e1rm: 150, bodyweightKg: 0) == nil)
    }
}
