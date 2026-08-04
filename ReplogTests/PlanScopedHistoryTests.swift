//
//  PlanScopedHistoryTests.swift
//  ReplogTests
//
//  A logged number belongs to the plan it was trained under. Inside one plan it spreads:
//  bench on Monday and Thursday's bench starts from what you just lifted. Across plans it
//  does not: a strength block's 100 kg must never rewrite a hypertrophy plan's 70 kg.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct PlanScopedHistoryTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    /// A plan holding one workout per entry in `workouts`, each prescribing `exIds` at
    /// `kg` x 10 for `sets` sets.
    @discardableResult
    private func seedPlan(_ ctx: ModelContext, named name: String,
                          workouts: [String] = ["Day 1"], exIds: [String] = ["Bench"],
                          sets: Int = 1, kg: Double = 50) -> Plan {
        let plan = Plan(name: name, order: 0)
        ctx.insert(plan)
        for (w, workoutName) in workouts.enumerated() {
            let workout = Workout(name: workoutName, day: Weekday.allCases[w % 7], order: w)
            workout.plan = plan
            ctx.insert(workout)
            for (i, exId) in exIds.enumerated() {
                let item = PlanItem(exId: exId, order: i)
                item.workout = workout
                ctx.insert(item)
                for s in 0..<sets {
                    let template = SetTemplate(weightKg: kg, reps: 10, rpe: 8, order: s, estimated: true)
                    template.item = item
                    ctx.insert(template)
                }
            }
        }
        try? ctx.save()
        return plan
    }

    /// Logs every set of `exId` at `kg` x `reps`, marks them done, and finishes the session
    /// the way the app does — so history is written with its plan attribution.
    private func trainAndFinish(_ ctx: ModelContext, workout: Workout,
                                exId: String, kg: Double, reps: Int = 8, date: Date = Date()) {
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let exercise = session.exercises.first { $0.exId == exId }!
        for set in exercise.orderedSets {
            set.weightKg = kg
            set.reps = reps
            set.done = true
        }
        try? ctx.save()
        SessionFinisher.finish(session, profile: ctx.userProfile(), context: ctx, date: date)
    }

    // MARK: - The reported bug: one plan bleeding into another

    @Test func anotherPlansNumbersDoNotSeedThisPlansSession() throws {
        let ctx = makeContext()
        let strength = seedPlan(ctx, named: "Strength", exIds: ["Bench"], kg: 50)
        let hypertrophy = seedPlan(ctx, named: "Hypertrophy", exIds: ["Bench"], kg: 70)

        // A heavy session under the Strength plan.
        trainAndFinish(ctx, workout: strength.orderedWorkouts[0], exId: "Bench", kg: 100, reps: 5)

        // The Hypertrophy plan is a different program. It starts from its own prescription.
        let session = SessionBuilder.start(workout: hypertrophy.orderedWorkouts[0], into: ctx)
        let bench = session.exercises.first { $0.exId == "Bench" }!
        #expect(bench.orderedSets.map(\.weightKg) == [70])
        #expect(bench.orderedSets.map(\.reps) == [10])
    }

    @Test func anotherPlansSessionIsNotShownAsThePreviousSet() throws {
        let ctx = makeContext()
        let a = seedPlan(ctx, named: "Plan A", exIds: ["Bench"], kg: 50)
        let b = seedPlan(ctx, named: "Plan B", exIds: ["Bench"], kg: 70)
        trainAndFinish(ctx, workout: a.orderedWorkouts[0], exId: "Bench", kg: 100, reps: 5)

        let session = SessionBuilder.start(workout: b.orderedWorkouts[0], into: ctx)
        let set = session.exercises.first { $0.exId == "Bench" }!.orderedSets[0]

        // No trend arrow against a lift from a different program: there is no "last time"
        // for this plan yet, and 100 kg from elsewhere is not a comparison.
        #expect(set.prevWeight == nil)
        #expect(set.prevReps == nil)
    }

    @Test func thisPlansOwnHistoryStillSeedsIt() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "Plan A", exIds: ["Bench"], kg: 50)
        let workout = plan.orderedWorkouts[0]
        trainAndFinish(ctx, workout: workout, exId: "Bench", kg: 60, reps: 8)

        // Scoping must not break the feature it scopes: within one plan, carry-forward works.
        let session = SessionBuilder.start(workout: workout, into: ctx)
        let set = session.exercises.first { $0.exId == "Bench" }!.orderedSets[0]
        #expect(set.weightKg == 60)
        #expect(set.reps == 8)
        #expect(set.prevWeight == 60)
    }

    // MARK: - Inside one plan the numbers do spread

    @Test func aSiblingWorkoutInTheSamePlanFollowsTheLastLog() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Push A", "Push B"],
                            exIds: ["Bench"], kg: 50)
        let pushA = plan.orderedWorkouts[0]
        let pushB = plan.orderedWorkouts[1]

        trainAndFinish(ctx, workout: pushA, exId: "Bench", kg: 62.5, reps: 8)

        // Same movement, same plan: Push B's prescription follows what was just lifted.
        let template = pushB.orderedItems[0].orderedSets[0]
        #expect(template.weightKg == 62.5)
        #expect(template.reps == 8)
        #expect(!template.estimated)
    }

    @Test func aWorkoutInAnotherPlanIsLeftAlone() throws {
        let ctx = makeContext()
        let ppl = seedPlan(ctx, named: "PPL", exIds: ["Bench"], kg: 50)
        let other = seedPlan(ctx, named: "Upper/Lower", exIds: ["Bench"], kg: 70)

        trainAndFinish(ctx, workout: ppl.orderedWorkouts[0], exId: "Bench", kg: 62.5, reps: 8)

        let untouched = other.orderedWorkouts[0].orderedItems[0].orderedSets[0]
        #expect(untouched.weightKg == 70)
        #expect(untouched.reps == 10)
        #expect(untouched.estimated)          // still an untouched seed
    }

    @Test func aSiblingNeverGrowsItsSetCount() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Push A", "Push B"],
                            exIds: ["Bench"], sets: 2, kg: 50)
        let pushA = plan.orderedWorkouts[0]
        let pushB = plan.orderedWorkouts[1]

        let session = SessionBuilder.start(workout: pushA, into: ctx)
        let bench = session.exercises.first!
        for set in bench.orderedSets { set.weightKg = 60; set.reps = 8; set.done = true }
        // An extra set on the day, beyond the prescription.
        let extra = LoggedSet(weightKg: 55, reps: 12, rpe: 8,
                              order: Reordering.nextOrder(after: bench.sets))
        extra.done = true
        extra.exercise = bench
        ctx.insert(extra)
        try ctx.save()

        TemplateWriteBack.applyIfComplete(session: session, context: ctx)

        // The source workout grew, because that is where the set was actually done.
        #expect(pushA.orderedItems[0].sets.count == 3)
        // Push B did not: "I did a fifth set on Monday" says nothing about Thursday.
        #expect(pushB.orderedItems[0].sets.count == 2)
        #expect(pushB.orderedItems[0].orderedSets.map(\.weightKg) == [60, 60])
    }

    @Test func aDeliberateSiblingEditOutranksAMirroredNumber() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Push A", "Push B"],
                            exIds: ["Bench"], kg: 50)
        let pushA = plan.orderedWorkouts[0]
        let pushB = plan.orderedWorkouts[1]

        let session = SessionBuilder.start(workout: pushA, into: ctx)
        let set = session.exercises.first!.orderedSets[0]
        set.weightKg = 60; set.reps = 8; set.done = true
        try ctx.save()

        // The athlete deliberately set Push B to 80 kg *after* this session happened.
        let sessionDate = Date()
        let siblingTemplate = pushB.orderedItems[0].orderedSets[0]
        siblingTemplate.weightKg = 80
        siblingTemplate.markEdited(at: sessionDate.addingTimeInterval(60))

        TemplateWriteBack.applyIfComplete(session: session, context: ctx, date: sessionDate)

        #expect(siblingTemplate.weightKg == 80)
    }

    @Test func anAdHocExerciseDoesNotAppearInASiblingWorkout() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Push A", "Push B"],
                            exIds: ["Bench"], kg: 50)
        let pushA = plan.orderedWorkouts[0]
        let pushB = plan.orderedWorkouts[1]

        let session = SessionBuilder.start(workout: pushA, into: ctx)
        for set in session.exercises.first!.orderedSets { set.weightKg = 60; set.reps = 8; set.done = true }
        // A movement the plan never prescribed, added on the day.
        let adHoc = SessionExercise(exId: "Flyes", order: 5)
        adHoc.session = session
        ctx.insert(adHoc)
        let adHocSet = LoggedSet(weightKg: 20, reps: 12, rpe: 8, order: 0)
        adHocSet.done = true
        adHocSet.exercise = adHoc
        ctx.insert(adHocSet)
        try ctx.save()

        TemplateWriteBack.applyIfComplete(session: session, context: ctx)

        #expect(pushA.orderedItems.map(\.exId) == ["Bench"])
        #expect(pushB.orderedItems.map(\.exId) == ["Bench"])
    }

    @Test func occurrencesMapPositionallyIntoASibling() throws {
        let ctx = makeContext()
        // Both workouts bench twice: a top set then a back-off block.
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Push A", "Push B"],
                            exIds: ["Bench", "Bench"], kg: 50)
        let pushA = plan.orderedWorkouts[0]
        let pushB = plan.orderedWorkouts[1]

        let session = SessionBuilder.start(workout: pushA, into: ctx)
        let ordered = session.exercises.sorted { $0.order < $1.order }
        for set in ordered[0].orderedSets { set.weightKg = 100; set.reps = 3; set.done = true }
        for set in ordered[1].orderedSets { set.weightKg = 80; set.reps = 8; set.done = true }
        try ctx.save()

        TemplateWriteBack.applyIfComplete(session: session, context: ctx)

        // Second occurrence writes to the second item, not both onto the first.
        #expect(pushB.orderedItems.map { $0.orderedSets[0].weightKg } == [100, 80])
        #expect(pushB.orderedItems.map { $0.orderedSets[0].reps } == [3, 8])
    }

    // MARK: - The store query

    @Test func historyQueryFiltersByPlan() throws {
        let ctx = makeContext()
        let a = seedPlan(ctx, named: "Plan A", exIds: ["Bench"], kg: 50)
        let b = seedPlan(ctx, named: "Plan B", exIds: ["Bench"], kg: 50)
        trainAndFinish(ctx, workout: a.orderedWorkouts[0], exId: "Bench", kg: 100, reps: 5)
        trainAndFinish(ctx, workout: b.orderedWorkouts[0], exId: "Bench", kg: 60, reps: 12)

        #expect(ctx.history(forExercise: "Bench").count == 2)
        #expect(ctx.history(forExercise: "Bench", inPlan: a.id).map(\.topW) == [100])
        #expect(ctx.history(forExercise: "Bench", inPlan: b.id).map(\.topW) == [60])
    }

    @Test func aSessionWithNoPlanSeesTheWholeTrail() throws {
        let ctx = makeContext()
        let a = seedPlan(ctx, named: "Plan A", exIds: ["Bench"], kg: 50)
        trainAndFinish(ctx, workout: a.orderedWorkouts[0], exId: "Bench", kg: 100, reps: 5)

        // No plan to respect, so nothing is filtered out.
        #expect(ctx.history(forExercise: "Bench", inPlan: nil).count == 1)
    }

    @Test func unattributableHistoryInfluencesNoPlan() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "Plan A", exIds: ["Bench"], kg: 50)
        // A row from a plan that has since been deleted.
        let orphan = HistoryEntry(exId: "Bench", date: Date(), topW: 140, topR: 1, e1rm: 145,
                                  sets: [RecordedSet(w: 140, r: 1)])
        ctx.insert(orphan)
        try ctx.save()

        #expect(ctx.history(forExercise: "Bench", inPlan: plan.id).isEmpty)
        // It is still real training, so the factual trail keeps it.
        #expect(ctx.history(forExercise: "Bench").count == 1)
    }

    // MARK: - Upgrading an existing athlete

    @Test func theBackfillResolvesPlanIdsFromWorkouts() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", exIds: ["Bench"], kg: 50)
        let workout = plan.orderedWorkouts[0]

        // History as it looked before plans were part of the record.
        let legacy = HistoryEntry(exId: "Bench", date: Date(), topW: 80, topR: 5, e1rm: 93,
                                  sets: [RecordedSet(w: 80, r: 5)], workoutId: workout.id)
        legacy.workoutName = workout.name
        ctx.insert(legacy)
        try ctx.save()
        #expect(legacy.planId == nil)

        SessionAttributionBackfill.run(context: ctx)

        // The athlete keeps their carry-forward instead of starting from zero.
        #expect(legacy.planId == plan.id)
        #expect(ctx.history(forExercise: "Bench", inPlan: plan.id).count == 1)
    }

    @Test func theBackfillLeavesUnresolvableRowsAlone() throws {
        let ctx = makeContext()
        seedPlan(ctx, named: "PPL", exIds: ["Bench"], kg: 50)
        // No workoutId, and its exercises match nothing well enough to attribute.
        let orphan = HistoryEntry(exId: "Kettlebell Swing", date: Date(), topW: 32, topR: 20,
                                  e1rm: 53, sets: [RecordedSet(w: 32, r: 20)])
        ctx.insert(orphan)
        try ctx.save()

        SessionAttributionBackfill.run(context: ctx)

        #expect(orphan.planId == nil)
    }
}
