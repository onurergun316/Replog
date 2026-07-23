//
//  TemplateWriteBackTests.swift
//  ReplogTests
//
//  Carrying a finished session's numbers back onto the plan: what you lifted becomes
//  what you start from next time — but only from a workout you actually completed, and
//  never by deleting prescription you didn't log against.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct TemplateWriteBackTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    /// One workout, `exIds` in order, each with `sets` estimated templates at 50 kg x 10.
    @discardableResult
    private func seedWorkout(_ ctx: ModelContext, exIds: [String] = ["Bench"],
                             sets: Int = 3) -> Workout {
        let plan = Plan(name: "PPL", order: 0); ctx.insert(plan)
        let workout = Workout(name: "Day 5", day: .fri, order: 0)
        workout.plan = plan; ctx.insert(workout)
        for (i, exId) in exIds.enumerated() {
            let item = PlanItem(exId: exId, order: i); item.workout = workout; ctx.insert(item)
            for s in 0..<sets {
                let template = SetTemplate(weightKg: 50, reps: 10, rpe: 8, order: s, estimated: true)
                template.item = item; ctx.insert(template)
            }
        }
        try? ctx.save()
        return workout
    }

    /// Logs `values` onto the session's sets in order and marks them done.
    private func log(_ session: ActiveSession, exId: String,
                     _ values: [(kg: Double, reps: Int)]) {
        let exercise = session.exercises.first { $0.exId == exId }!
        for (set, value) in zip(exercise.orderedSets, values) {
            set.weightKg = value.kg
            set.reps = value.reps
            set.done = true
        }
    }

    // MARK: - The reported bug

    @Test func completedSessionOverwritesTheTemplates() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        log(session, exId: "Bench", [(60, 8), (60, 8), (57.5, 7)])
        try ctx.save()

        let written = TemplateWriteBack.applyIfComplete(session: session, context: ctx)

        #expect(written == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 60, 57.5])
        #expect(templates.map(\.reps) == [8, 8, 7])
        // These are real logged numbers now, not a computed seed.
        #expect(templates.allSatisfy { !$0.estimated })
    }

    @Test func nextSessionStartsFromWhatWasLogged() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        let first = SessionBuilder.start(workout: workout, into: ctx)
        log(first, exId: "Bench", [(60, 8), (60, 8), (57.5, 7)])
        try ctx.save()
        TemplateWriteBack.applyIfComplete(session: first, context: ctx)
        ctx.delete(first)
        try ctx.save()

        // The whole point: the next session seeds from last time, not from the plan's
        // original 50 x 10 estimate.
        let second = SessionBuilder.start(workout: workout, into: ctx)
        let bench = second.exercises.first { $0.exId == "Bench" }!
        #expect(bench.orderedSets.map(\.weightKg) == [60, 60, 57.5])
        #expect(bench.orderedSets.map(\.reps) == [8, 8, 7])
    }

    @Test func rpeCarriesForwardToo() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 1)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let set = session.exercises.first!.orderedSets[0]
        set.rpe = 10
        set.done = true
        try ctx.save()

        TemplateWriteBack.applyIfComplete(session: session, context: ctx)
        #expect(workout.orderedItems[0].orderedSets[0].rpe == 10)
    }

    // MARK: - Only a complete workout writes back

    @Test func incompleteSessionLeavesThePlanAlone() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 3)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.exercises.first!
        // Two of three sets logged — a partial session is not evidence the plan changed.
        for set in bench.orderedSets.prefix(2) { set.weightKg = 60; set.done = true }
        try ctx.save()

        let written = TemplateWriteBack.applyIfComplete(session: session, context: ctx)

        #expect(written == 0)
        #expect(workout.orderedItems[0].orderedSets.allSatisfy { $0.weightKg == 50 })
        #expect(workout.orderedItems[0].orderedSets.allSatisfy { $0.estimated })
    }

    @Test func sessionWithoutASourceWorkoutIsANoOp() throws {
        let ctx = makeContext()
        let session = ActiveSession(workoutId: nil, name: "Ad hoc", planName: "")
        ctx.insert(session)
        let exercise = SessionExercise(exId: "Bench", order: 0)
        exercise.session = session; ctx.insert(exercise)
        let set = LoggedSet(weightKg: 60, reps: 8, rpe: 8, order: 0)
        set.done = true; set.exercise = exercise; ctx.insert(set)
        try ctx.save()

        #expect(TemplateWriteBack.applyIfComplete(session: session, context: ctx) == 0)
    }

    @Test func deletedSourceWorkoutIsANoOp() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 1)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        session.exercises.first!.orderedSets[0].done = true
        try ctx.save()

        // The athlete deleted the plan while the session was paused.
        ctx.delete(workout)
        try ctx.save()

        #expect(TemplateWriteBack.applyIfComplete(session: session, context: ctx) == 0)
    }

    // MARK: - Set-count mismatches

    @Test func extraLoggedSetsAppendNewTemplates() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 2)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.exercises.first!
        // The athlete tapped "Add set" for a third.
        let extra = LoggedSet(weightKg: 55, reps: 6, rpe: 9, order: 2)
        extra.exercise = bench; ctx.insert(extra)
        log(session, exId: "Bench", [(60, 8), (60, 8), (55, 6)])
        try ctx.save()

        let written = TemplateWriteBack.apply(session: session, to: workout, context: ctx)
        try ctx.save()

        #expect(written == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.count == 3)
        #expect(templates.map(\.weightKg) == [60, 60, 55])
        #expect(templates.map(\.order) == [0, 1, 2])   // contiguous, no collision
    }

    @Test func trimmedSessionLeavesSurplusTemplatesIntact() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 3)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        // Readiness modulation trimmed the last set: only two were ever presented.
        let bench = session.exercises.first!
        ctx.delete(bench.orderedSets[2])
        try ctx.save()
        log(session, exId: "Bench", [(60, 8), (60, 8)])
        try ctx.save()

        TemplateWriteBack.apply(session: session, to: workout, context: ctx)

        // A bad-sleep day must not permanently shrink the plan.
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.count == 3)
        #expect(templates.map(\.weightKg) == [60, 60, 50])
        #expect(templates[2].estimated)               // never logged against, still a seed
    }

    @Test func anUndoneSetDoesNotShiftTheOnesAfterIt() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 3)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let sets = session.exercises.first!.orderedSets
        sets[0].weightKg = 60; sets[0].done = true
        sets[1].weightKg = 70                                  // skipped, left undone
        sets[2].weightKg = 80; sets[2].done = true
        try ctx.save()

        TemplateWriteBack.apply(session: session, to: workout, context: ctx)

        // Set 3's numbers land on template 3, not slid up into template 2's slot.
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 50, 80])
        #expect(templates[1].estimated)
    }

    // MARK: - Matching

    @Test func duplicateExerciseMatchesItemsInOrder() throws {
        let ctx = makeContext()
        // Same lift twice: a heavy top set, then a back-off block.
        let workout = seedWorkout(ctx, exIds: ["Bench", "Bench"], sets: 1)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let occurrences = session.exercises.sorted { $0.order < $1.order }
        occurrences[0].orderedSets[0].weightKg = 100; occurrences[0].orderedSets[0].done = true
        occurrences[1].orderedSets[0].weightKg = 70;  occurrences[1].orderedSets[0].done = true
        try ctx.save()

        TemplateWriteBack.apply(session: session, to: workout, context: ctx)

        let items = workout.orderedItems
        #expect(items[0].orderedSets[0].weightKg == 100)   // top set -> first item
        #expect(items[1].orderedSets[0].weightKg == 70)    // back-off -> second item
    }

    @Test func adHocExerciseDoesNotTouchThePlan() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, exIds: ["Bench"], sets: 1)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        // An exercise added mid-workout that the plan never prescribed.
        let adHoc = SessionExercise(exId: "Curl", order: 5)
        adHoc.session = session; ctx.insert(adHoc)
        let set = LoggedSet(weightKg: 20, reps: 12, rpe: 8, order: 0)
        set.done = true; set.exercise = adHoc; ctx.insert(set)
        session.exercises.first { $0.exId == "Bench" }!.orderedSets[0].done = true
        try ctx.save()

        TemplateWriteBack.apply(session: session, to: workout, context: ctx)

        #expect(workout.items.count == 1)                       // no item invented
        #expect(workout.orderedItems[0].exId == "Bench")
    }

    @Test func matchesPairsByExIdAndSkipsUnknowns() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, exIds: ["Bench", "Row"], sets: 1)
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let adHoc = SessionExercise(exId: "Curl", order: 9)
        adHoc.session = session; ctx.insert(adHoc)
        try ctx.save()

        let pairs = TemplateWriteBack.matches(sessionExercises: session.exercises,
                                              items: workout.items)

        #expect(pairs.count == 2)
        #expect(pairs.map(\.exercise.exId) == ["Bench", "Row"])
        #expect(pairs.allSatisfy { $0.exercise.exId == $0.item.exId })
    }
}
