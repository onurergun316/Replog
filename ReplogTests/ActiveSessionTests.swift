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

    @Test func finishCompleteWorkoutWritesHistoryAndStreak() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        // Schedule the workout on today's weekday so completing it today counts.
        let fixedDay = Date()
        workout.day = Weekday.from(fixedDay)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        // Complete EVERY exercise so the workout is fully complete (Bench top is 70x10).
        session.exercises.forEach { $0.sets.forEach { $0.done = true } }
        try ctx.save()
        #expect(session.isComplete)

        let summary = SessionFinisher.finish(session, profile: profile, context: ctx, date: fixedDay)
        try ctx.save()

        #expect(summary.exercisesLogged == 2)
        #expect(summary.countedAsComplete == true)
        #expect(summary.newStreak == 1)             // today's scheduled workout done
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

    @Test func partialFinishSavesHistoryButDoesNotCountTheDay() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        // Complete only Bench (Press left undone) → workout is not fully complete.
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        bench.sets.forEach { $0.done = true }

        let summary = SessionFinisher.finish(session, profile: profile, context: ctx, date: Date())
        try ctx.save()

        #expect(summary.countedAsComplete == false)
        #expect(summary.exercisesLogged == 1)            // Bench history still saved
        #expect(ctx.history(forExercise: "Bench").count == 1)
        #expect(profile.totalWorkouts == 0)              // incomplete workout doesn't count
        #expect(profile.doneDates.isEmpty)               // day not marked complete
    }

    @Test func finishCarriesLoggedValuesOntoThePlan() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let fixedDay = Date()
        workout.day = Weekday.from(fixedDay)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        // The athlete lifted heavier and lower-rep than the plan's 60/70 x 10.
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        bench.orderedSets[0].weightKg = 80; bench.orderedSets[0].reps = 5
        bench.orderedSets[1].weightKg = 85; bench.orderedSets[1].reps = 3
        session.exercises.forEach { $0.sets.forEach { $0.done = true } }
        try ctx.save()

        SessionFinisher.finish(session, profile: profile, context: ctx, date: fixedDay)
        try ctx.save()

        let templates = workout.orderedItems.first { $0.exId == "Bench" }!.orderedSets
        #expect(templates.map(\.weightKg) == [80, 85])
        #expect(templates.map(\.reps) == [5, 3])
    }

    @Test func partialFinishLeavesThePlanUnchanged() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        // Only Bench logged; Press untouched → the workout is not complete.
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        bench.orderedSets.forEach { $0.weightKg = 999; $0.done = true }

        SessionFinisher.finish(session, profile: profile, context: ctx, date: Date())
        try ctx.save()

        // History is still saved (see partialFinishSavesHistoryButDoesNotCountTheDay),
        // but a half-done workout is not evidence the prescription changed.
        let templates = workout.orderedItems.first { $0.exId == "Bench" }!.orderedSets
        #expect(templates.map(\.weightKg) == [60, 70])
    }

    @Test func sessionInheritsPerExerciseRestFromPlan() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let items = workout.orderedItems
        items[0].restSeconds = 45     // Bench: custom rest
        items[1].restSeconds = nil    // Press: use app default
        try ctx.save()

        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        let press = session.orderedExercises.first { $0.exId == "Press" }!
        #expect(bench.restSeconds == 45)
        #expect(press.restSeconds == nil)
    }

    @Test func pausingKeepsSessionResumable() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        session.orderedExercises.first?.orderedSets.first?.done = true
        try ctx.save()

        // "Save for later" pauses instead of finishing: the session persists (not deleted)
        // and stays resumable with its progress intact.
        session.isOpen = false
        try ctx.save()

        let stored = try ctx.fetch(FetchDescriptor<ActiveSession>())
        #expect(stored.count == 1)
        #expect(stored.first?.isOpen == false)
        #expect(stored.first?.completedSets == 1)
    }

    // MARK: - Progression suggestions (B2)

    /// Three sessions of rising e1RM, mid rep range.
    private func seedProgressingHistory(_ ctx: ModelContext, exId: String, topR: Int = 9) {
        for (i, w) in [56.0, 58.0, 60.0].enumerated() {
            let entry = HistoryEntry(
                exId: exId, date: Date().addingTimeInterval(Double(i - 3) * 86_400),
                topW: w, topR: topR, e1rm: Formulas.e1rmRounded(kg: w, reps: topR),
                sets: [RecordedSet(w: w, r: topR)])
            ctx.insert(entry)
        }
        try? ctx.save()
    }

    @Test func startAttachesEngineSuggestionFromHistory() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedProgressingHistory(ctx, exId: "Bench")

        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!

        // The stored suggestion is exactly what the engine recommends for this history.
        let expected = ProgressionEngine.recommend(
            exId: "Bench", history: ctx.history(forExercise: "Bench"),
            goal: ctx.userProfile().goal, units: ctx.appSettings().units)
        #expect(bench.suggestion == expected)
        #expect(bench.suggestion?.action == .increaseReps)   // progressing, mid-range
        #expect(bench.suggestion?.suggestedReps == 10)
        #expect(bench.suggestion?.suggestedWeightKg == 60)
        #expect(bench.suggestionDismissed == false)
    }

    @Test func startWithoutHistoryHasNoSuggestion() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        #expect(session.exercises.allSatisfy { $0.suggestion == nil })
    }

    @Test func suggestionRespectsProfileGoal() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        ctx.userProfile().goal = .loseWeight            // rep range 12...15
        seedProgressingHistory(ctx, exId: "Bench", topR: 15)

        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        // Top of the fat-loss range reached -> add load, rebuild from the range floor.
        #expect(bench.suggestion?.action == .increaseLoad)
        #expect(bench.suggestion?.suggestedWeightKg == 62.5)
        #expect(bench.suggestion?.suggestedReps == 12)
    }

    @Test func suggestionSurvivesPersistenceRoundTrip() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedProgressingHistory(ctx, exId: "Bench")
        let built = SessionBuilder.start(workout: workout, into: ctx)
        let suggestion = built.orderedExercises.first { $0.exId == "Bench" }!.suggestion
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SessionExercise>())
            .first { $0.exId == "Bench" }
        #expect(fetched?.suggestion == suggestion)
        #expect(suggestion != nil)
    }

    @Test func applySuggestionUpdatesOnlyUndoneSets() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedProgressingHistory(ctx, exId: "Bench")
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!

        // The user already logged set 1 with their own numbers.
        let logged = bench.orderedSets[0]
        logged.weightKg = 100
        logged.reps = 3
        logged.done = true

        bench.applySuggestion()

        #expect(logged.weightKg == 100)                 // logged set untouched
        #expect(logged.reps == 3)
        let pending = bench.orderedSets[1]
        #expect(pending.weightKg == 60)                 // suggestion applied
        #expect(pending.reps == 10)
        #expect(bench.suggestionDismissed)              // banner retired after apply
    }

    @Test func applyWithoutSuggestionIsANoOp() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!
        let before = bench.orderedSets.map { ($0.weightKg, $0.reps) }

        bench.applySuggestion()

        #expect(bench.orderedSets.map(\.weightKg) == before.map(\.0))
        #expect(bench.orderedSets.map(\.reps) == before.map(\.1))
        #expect(bench.suggestionDismissed == false)     // nothing to retire
    }

    @Test func dismissedSuggestionPersists() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedProgressingHistory(ctx, exId: "Bench")
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.orderedExercises.first { $0.exId == "Bench" }!

        bench.suggestionDismissed = true
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SessionExercise>())
            .first { $0.exId == "Bench" }
        #expect(fetched?.suggestionDismissed == true)
        #expect(fetched?.suggestion != nil)             // still stored, just hidden
    }

    @Test func suggestionAccessorRoundTripsAndClears() throws {
        let exercise = SessionExercise(exId: "Row")
        let rec = ProgressionRecommendation(
            exId: "Row", action: .deload,
            suggestedWeightKg: 52.5, suggestedReps: 8, reason: "Deload and rebuild.")
        exercise.suggestion = rec
        #expect(exercise.suggestion == rec)
        exercise.suggestion = nil
        #expect(exercise.suggestion == nil)
        #expect(exercise.suggestionActionRaw == nil)
    }

    @Test func finishWithNoCompletedSetsCountsNothing() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let profile = ctx.userProfile()

        let summary = SessionFinisher.finish(session, profile: profile, context: ctx)
        #expect(summary.exercisesLogged == 0)
        #expect(summary.countedAsComplete == false)
        #expect(ctx.history(forExercise: "Bench").isEmpty)
        #expect(profile.totalWorkouts == 0)              // nothing done → nothing counts
    }
}
