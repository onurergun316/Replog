//
//  CoachContextBuilderTests.swift
//  ReplogTests
//
//  The MainActor glue that turns a live session into a SessionOutcome (PR-vs-prior detection,
//  volume math) and records the right insights into the coaching memory.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct CoachContextBuilderTests {

    /// A workout of two 3-set exercises in a fresh store, with the session's sets marked done
    /// at the given weight/reps.
    private func makeSession(context: ModelContext) -> ActiveSession {
        let plan = PlanFactory.emptyPlan(name: "P", into: context, order: 0)
        let workout = PlanFactory.addWorkout(to: plan, into: context)
        PlanFactory.addExercise("A", to: workout, into: context)
        PlanFactory.addExercise("B", to: workout, into: context)
        try? context.save()
        return SessionBuilder.start(workout: workout, into: context)
    }

    private func markDone(_ exercise: SessionExercise, w: Double, r: Int) {
        for set in exercise.sets { set.weightKg = w; set.reps = r; set.done = true }
    }

    @Test func sessionOutcomeDetectsPRsAndVolume() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        // Prior best for A: e1RM 100 from a 900 kg session.
        context.insert(HistoryEntry(exId: "A", date: Date(timeIntervalSince1970: 1_749_000_000),
                                    topW: 90, topR: 5, e1rm: 100,
                                    sets: [RecordedSet(w: 90, r: 5), RecordedSet(w: 90, r: 5)]))
        let session = makeSession(context: context)
        let a = try #require(session.orderedExercises.first { $0.exId == "A" })
        let b = try #require(session.orderedExercises.first { $0.exId == "B" })
        markDone(a, w: 100, r: 5)   // e1RM 116 > prior 100 → PR
        markDone(b, w: 50, r: 5)    // no prior → not a PR
        try context.save()

        let outcome = CoachContextBuilder.sessionOutcome(from: session, context: context)
        #expect(outcome.lifts.count == 2)
        let liftA = try #require(outcome.lifts.first { $0.exId == "A" })
        let liftB = try #require(outcome.lifts.first { $0.exId == "B" })
        #expect(liftA.isPR)
        #expect(!liftB.isPR)                          // first-ever session is not a "PR"
        #expect(outcome.prCount == 1)
        #expect(liftA.volumeKg == 1500)              // 3 × 100 × 5
        #expect(liftB.volumeKg == 750)               // 3 × 50 × 5
        #expect(outcome.totalVolumeKg == 2250)
        #expect(outcome.previousTotalVolumeKg == 900) // A's prior session volume
    }

    @Test func recordDebriefStoresOnlyDebriefAndMilestoneInsights() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let insights = [
            CoachInsight(kind: .sessionDebrief, priority: .normal, title: "d", body: "b"),
            CoachInsight(kind: .milestone, priority: .high, title: "pr", body: "b"),
            CoachInsight(kind: .stallAlert, priority: .high, title: "stall", body: "b"),
        ]
        let logs = CoachContextBuilder.recordDebrief(insights, context: context)
        try context.save()
        // The stall alert is owned by StallDetector — not re-recorded here.
        #expect(logs.count == 2)
        #expect(context.coachingLogs(kind: .coachInsight).count == 2)
    }

    @Test func recordDailyCardIsAtMostOncePerDay() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let insight = CoachInsight(kind: .checkInPrompt, priority: .low, title: "weigh-in", body: "b")

        #expect(CoachContextBuilder.recordDailyCard(insight, context: context, now: day) != nil)
        // A second card the same day is suppressed.
        #expect(CoachContextBuilder.recordDailyCard(insight, context: context, now: day) == nil)
        #expect(context.coachingLogs(kind: .coachInsight).count == 1)
    }

    @Test func recordDailyCardNeverRecordsAStallAlert() {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let stall = CoachInsight(kind: .stallAlert, priority: .high, title: "stall", body: "b", exId: "A")
        #expect(CoachContextBuilder.recordDailyCard(stall, context: context) == nil)
        #expect(context.coachingLogs(kind: .coachInsight).isEmpty)
    }

    // MARK: - The debrief context

    @Test func theDebriefContextCarriesTheSessionAndTheAthleteIntoTheEngine() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let older = Date(timeIntervalSince1970: 1_749_000_000)
        context.insert(HistoryEntry(exId: "A", date: older, topW: 90, topR: 5, e1rm: 100,
                                    sets: [RecordedSet(w: 90, r: 5)]))
        let session = makeSession(context: context)
        let a = try #require(session.orderedExercises.first { $0.exId == "A" })
        let b = try #require(session.orderedExercises.first { $0.exId == "B" })
        markDone(a, w: 100, r: 5)
        markDone(b, w: 50, r: 5)
        try context.save()

        let outcome = CoachContextBuilder.sessionOutcome(from: session, context: context)
        let profile = context.userProfile()
        profile.goal = .loseWeight
        profile.streak = 4
        profile.weekStreak = 2
        let settings = context.appSettings()
        settings.units = .lb

        let ctx = CoachContextBuilder.debriefContext(
            outcome: outcome, profile: profile, settings: settings,
            programDeloadRule: "Drop 10% and rebuild", context: context)

        #expect(ctx.justFinished == outcome)
        #expect(ctx.goal == .loseWeight)
        #expect(ctx.units == .lb)
        #expect(ctx.workoutStreak == 4)
        #expect(ctx.weekStreak == 2)
        #expect(ctx.programDeloadRule == "Drop 10% and rebuild")
        // Every finished lift arrives named, with its own trail attached.
        #expect(Set(ctx.exerciseNames.keys) == ["A", "B"])
        #expect(ctx.historyByExercise["A"]?.count == 1)
        // Somebody who just finished a session is by definition not a fresh user.
        #expect(!ctx.isFreshUser)
    }

    @Test func aDebriefWithNoLiftsCarriesNoHistory() {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let outcome = SessionOutcome(lifts: [], totalVolumeKg: 0,
                                     previousTotalVolumeKg: nil, isFullyComplete: false)
        let ctx = CoachContextBuilder.debriefContext(
            outcome: outcome, profile: context.userProfile(), settings: context.appSettings(),
            programDeloadRule: nil, context: context)

        #expect(ctx.historyByExercise.isEmpty)
        #expect(ctx.exerciseNames.isEmpty)
        #expect(ctx.programDeloadRule == nil)
    }
}
