//
//  PlanExerciseSyncTests.swift
//  ReplogTests
//
//  Editing a movement edits it everywhere that plan prescribes it — and nowhere else.
//  A plan benching on Monday and Thursday holds one bench prescription, so raising
//  Monday's load raises Thursday's. A second plan's bench is a different programme's
//  number and must never move.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct PlanExerciseSyncTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    /// A plan whose every workout prescribes `exIds`, `sets` sets of `kg` x `reps`.
    @discardableResult
    private func seedPlan(_ ctx: ModelContext, named name: String,
                          workouts: [String] = ["Monday", "Thursday"],
                          exIds: [String] = ["Bench"],
                          sets: Int = 3, kg: Double = 60, reps: Int = 10) -> Plan {
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
                    let template = SetTemplate(weightKg: kg, reps: reps, rpe: 8, order: s)
                    template.item = item
                    ctx.insert(template)
                }
            }
        }
        try? ctx.save()
        return plan
    }

    private func item(_ plan: Plan, workout name: String, exId: String = "Bench",
                      occurrence: Int = 0) throws -> PlanItem {
        let workout = try #require(plan.workouts.first { $0.name == name })
        return try #require(workout.orderedItems.filter { $0.exId == exId }[safe: occurrence])
    }

    // MARK: - The rule: one plan, one prescription per movement

    @Test func editingTheWeightMovesEveryWorkoutInThePlan() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", kg: 60)
        let monday = try item(plan, workout: "Monday")

        monday.orderedSets[0].weightKg = 80
        monday.orderedSets[0].markEdited()
        #expect(PlanExerciseSync.mirror(monday, context: ctx) == 1)

        let thursday = try item(plan, workout: "Thursday")
        #expect(thursday.orderedSets[0].weightKg == 80)
        #expect(thursday.orderedSets[0].estimated == false)
        // The mirrored number carries the edit's timestamp, so a session logged before the
        // edit cannot overwrite it on the sibling day either.
        #expect(thursday.orderedSets[0].updatedAt == monday.orderedSets[0].updatedAt)
    }

    @Test func editingRepsMovesEveryWorkoutInThePlan() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", reps: 10)
        let monday = try item(plan, workout: "Monday")

        for set in monday.orderedSets { set.reps = 5 }
        PlanExerciseSync.mirror(monday, context: ctx)

        let thursday = try item(plan, workout: "Thursday")
        #expect(thursday.orderedSets.allSatisfy { $0.reps == 5 })
    }

    @Test func addingASetAddsItToEveryWorkoutInThePlan() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", sets: 3)
        let monday = try item(plan, workout: "Monday")

        let added = SetTemplate(weightKg: 60, reps: 8, rpe: 9,
                                order: Reordering.nextOrder(after: monday.sets))
        added.item = monday
        ctx.insert(added)
        PlanExerciseSync.mirror(monday, context: ctx)

        let thursday = try item(plan, workout: "Thursday")
        #expect(thursday.sets.count == 4)
        #expect(thursday.orderedSets[3].reps == 8)
        #expect(thursday.orderedSets[3].rpe == 9)
    }

    @Test func removingASetRemovesItFromEveryWorkoutInThePlan() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", sets: 3)
        let monday = try item(plan, workout: "Monday")

        ctx.delete(monday.orderedSets[2])
        // Saved first, exactly as the editor does: a pending delete is not yet off the
        // relationship, so mirroring before the save would copy the set right back.
        try? ctx.save()
        PlanExerciseSync.mirror(monday, context: ctx)
        // And saved again, because a pending delete is likewise not off the sibling's
        // relationship until it is. The editor saves after every mirror for this reason.
        try? ctx.save()

        let thursday = try item(plan, workout: "Thursday")
        #expect(thursday.sets.count == 2)
    }

    @Test func aThirdWorkoutInThePlanFollowsToo() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Mon", "Wed", "Fri"], kg: 60)
        let monday = try item(plan, workout: "Mon")

        for set in monday.orderedSets { set.weightKg = 75 }
        #expect(PlanExerciseSync.mirror(monday, context: ctx) == 2)

        for name in ["Wed", "Fri"] {
            let mirrored = try item(plan, workout: name)
            #expect(mirrored.orderedSets.allSatisfy { $0.weightKg == 75 })
        }
    }

    // MARK: - The boundary: never another plan

    @Test func anotherPlansPrescriptionIsUntouched() throws {
        let ctx = makeContext()
        let planA = seedPlan(ctx, named: "Plan A", workouts: ["Monday", "Thursday"], kg: 60)
        let planB = seedPlan(ctx, named: "Plan B", workouts: ["Monday", "Friday"], kg: 100)

        let source = try item(planA, workout: "Monday")
        for set in source.orderedSets { set.weightKg = 80 }
        PlanExerciseSync.mirror(source, context: ctx)

        let mirrored = try item(planA, workout: "Thursday")
        #expect(mirrored.orderedSets[0].weightKg == 80)
        for name in ["Monday", "Friday"] {
            let untouched = try item(planB, workout: name)
            #expect(untouched.orderedSets[0].weightKg == 100)
        }
    }

    // MARK: - Occurrence matching

    @Test func theSecondOccurrenceMirrorsOntoTheSecondOccurrence() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Monday", "Thursday"],
                            exIds: ["Bench", "Bench"], sets: 1, kg: 60)

        let backOff = try item(plan, workout: "Monday", occurrence: 1)
        backOff.orderedSets[0].weightKg = 45
        PlanExerciseSync.mirror(backOff, context: ctx)

        let topSet = try item(plan, workout: "Thursday", occurrence: 0)
        let mirroredBackOff = try item(plan, workout: "Thursday", occurrence: 1)
        #expect(topSet.orderedSets[0].weightKg == 60)
        #expect(mirroredBackOff.orderedSets[0].weightKg == 45)
    }

    @Test func aWorkoutTrainingTheMovementFewerTimesKeepsWhatItHas() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", workouts: ["Monday"], exIds: ["Bench", "Bench"],
                            sets: 1, kg: 60)
        // Thursday benches once; Monday benches twice.
        let thursday = Workout(name: "Thursday", day: .thu, order: 1)
        thursday.plan = plan
        ctx.insert(thursday)
        let single = PlanItem(exId: "Bench", order: 0)
        single.workout = thursday
        ctx.insert(single)
        let set = SetTemplate(weightKg: 60, reps: 10, rpe: 8, order: 0)
        set.item = single
        ctx.insert(set)
        try? ctx.save()

        let backOff = try item(plan, workout: "Monday", occurrence: 1)
        backOff.orderedSets[0].weightKg = 45
        #expect(PlanExerciseSync.mirror(backOff, context: ctx) == 0)
        #expect(single.orderedSets[0].weightKg == 60)
    }

    // MARK: - Scope

    @Test func onlyTheEditedMovementMoves() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", exIds: ["Bench", "Squat"], kg: 60)
        let bench = try item(plan, workout: "Monday", exId: "Bench")

        for set in bench.orderedSets { set.weightKg = 80 }
        PlanExerciseSync.mirror(bench, context: ctx)

        let mirroredBench = try item(plan, workout: "Thursday", exId: "Bench")
        let squat = try item(plan, workout: "Thursday", exId: "Squat")
        #expect(mirroredBench.orderedSets[0].weightKg == 80)
        #expect(squat.orderedSets[0].weightKg == 60)
    }

    @Test func aMovementNoOtherWorkoutPrescribesMirrorsNowhere() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL", exIds: ["Bench"])
        let extra = PlanItem(exId: "Curl", order: 1)
        extra.workout = plan.orderedWorkouts[0]
        ctx.insert(extra)
        let set = SetTemplate(weightKg: 15, reps: 12, rpe: 8, order: 0)
        set.item = extra
        ctx.insert(set)
        try? ctx.save()

        #expect(PlanExerciseSync.siblings(of: extra).isEmpty)
        #expect(PlanExerciseSync.mirror(extra, context: ctx) == 0)
    }

    @Test func mirroringAnUnchangedPrescriptionReportsNoChange() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx, named: "PPL")
        let monday = try item(plan, workout: "Monday")
        #expect(PlanExerciseSync.mirror(monday, context: ctx) == 0)
    }

    @Test func anOrphanItemHasNoOccurrenceAndNoSiblings() {
        let ctx = makeContext()
        let orphan = PlanItem(exId: "Bench", order: 0)
        ctx.insert(orphan)

        #expect(PlanExerciseSync.occurrenceIndex(of: orphan) == nil)
        #expect(PlanExerciseSync.siblings(of: orphan).isEmpty)
        #expect(PlanExerciseSync.mirror(orphan, context: ctx) == 0)
    }

    @Test func aWorkoutWithNoPlanMirrorsNowhere() {
        let ctx = makeContext()
        let workout = Workout(name: "Loose", day: .mon, order: 0)
        ctx.insert(workout)
        let item = PlanItem(exId: "Bench", order: 0)
        item.workout = workout
        ctx.insert(item)

        #expect(PlanExerciseSync.occurrenceIndex(of: item) == 0)
        #expect(PlanExerciseSync.siblings(of: item).isEmpty)
    }

    // MARK: - `SetTemplate.matches`

    @Test func matchesComparesEveryMirroredField() {
        let now = Date()
        let a = SetTemplate(weightKg: 60, reps: 10, rpe: 8, order: 0)
        let b = SetTemplate(weightKg: 60, reps: 10, rpe: 8, order: 0)
        #expect(a.matches(b))

        b.reps = 9
        #expect(!a.matches(b))
        b.reps = 10
        b.rpe = 9
        #expect(!a.matches(b))
        b.rpe = 8
        b.estimated = true
        #expect(!a.matches(b))
        b.estimated = false
        b.order = 1
        #expect(!a.matches(b))
        b.order = 0
        b.updatedAt = now
        #expect(!a.matches(b))
        a.updatedAt = now
        #expect(a.matches(b))
    }
}
