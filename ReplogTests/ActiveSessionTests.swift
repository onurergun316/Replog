//
//  ActiveSessionTests.swift
//  ReplogTests
//
//  The core loop: building a session from a workout, completing sets, reordering
//  finished exercises, and finishing (history + streak + calendar).
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct ActiveSessionTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    /// Builds a one-plan, one-workout, two-exercise setup with prescribed sets.
    private func seedWorkout(_ ctx: ModelContext) -> Workout {
        let plan = Plan(name: "PPL", order: 0); ctx.insert(plan)
        let workout = Workout(name: "Push Day", day: .mon, order: 0); workout.plan = plan; ctx.insert(workout)
        for (i, exId) in ["Bench", "Press"].enumerated() {
            let item = PlanItem(exId: exId, order: i); item.workout = workout; ctx.insert(item)
            for s in 0..<2 {
                let set = SetTemplate(weightKg: 60 + Double(s * 10), reps: 10, rpe: 8, order: s)
                set.item = item; ctx.insert(set)
            }
        }
        try? ctx.save()
        return workout
    }

    @Test func startBuildsSessionFromTemplates() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        try ctx.save()

        #expect(session.exercises.count == 2)
        #expect(session.totalSets == 4)
        #expect(session.name == "Push Day")
        let bench = session.orderedExercises.first { $0.exId == "Bench" }
        #expect(bench?.orderedSets.map(\.weightKg) == [60, 70])
        // No history yet -> prev values nil.
        #expect(bench?.orderedSets.allSatisfy { $0.prevWeight == nil } == true)
    }

    @Test func startPrefillsPreviousFromHistory() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        // Seed prior history for "Bench" with two sets.
        let entry = HistoryEntry(exId: "Bench", date: Date().addingTimeInterval(-86_400),
                                 topW: 65, topR: 9, e1rm: 84,
                                 sets: [RecordedSet(w: 65, r: 9), RecordedSet(w: 75, r: 7)])
        ctx.insert(entry); try ctx.save()

        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        #expect(bench.orderedSets[0].prevWeight == 65)
        #expect(bench.orderedSets[0].prevReps == 9)
        #expect(bench.orderedSets[1].prevWeight == 75)
        #expect(bench.orderedSets[1].prevReps == 7)
        // Trend: current 60 < prev 65 -> down.
        #expect(bench.orderedSets[0].weightTrend == .down)
    }

    @Test func completingAllSetsMarksExerciseDoneAndSortsToBottom() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!

        for set in bench.sets { set.done = true }
        bench.doneOrder = 0
        #expect(bench.isDone)
        // Done exercise sorts after the unfinished one.
        #expect(session.orderedExercises.last?.exId == "Bench")
        #expect(session.completedSets == 2)
        #expect(!session.isComplete)
    }

    @Test func finishWritesTopSetHistoryAndStreak() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        // Complete the Bench exercise: 60x10 and 70x10 -> top by e1RM is 70x10.
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        bench.sets.forEach { $0.done = true }

        let fixedDay = Date()
        let summary = SessionFinisher.finish(session, profile: profile, context: ctx, date: fixedDay)
        try ctx.save()

        #expect(summary.exercisesLogged == 1)        // only Bench had completed sets
        #expect(summary.newStreak == 1)
        #expect(profile.totalWorkouts == 1)
        #expect(profile.doneDates.count == 1)

        let history = ctx.history(forExercise: "Bench")
        #expect(history.count == 1)
        #expect(history.first?.topW == 70)
        #expect(history.first?.topR == 10)
        #expect(history.first?.e1rm == Formulas.e1rmRounded(kg: 70, reps: 10))
        #expect(history.first?.sets.count == 2)

        // Session removed after finishing.
        #expect(try ctx.fetch(FetchDescriptor<ActiveSession>()).isEmpty)
    }

    @Test func finishWithNoCompletedSetsLogsNothingButStillCountsDay() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        let summary = SessionFinisher.finish(session, profile: profile, context: ctx)
        #expect(summary.exercisesLogged == 0)
        #expect(ctx.history(forExercise: "Bench").isEmpty)
        #expect(profile.totalWorkouts == 1) // finishing still records the day
    }
}
