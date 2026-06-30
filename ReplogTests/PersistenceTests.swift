//
//  PersistenceTests.swift
//  ReplogTests
//
//  SwiftData behavior against an in-memory container: building the onion,
//  cascade deletes, ordering, singletons, and generated-plan materialization.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct PersistenceTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    @Test func buildsPlanWorkoutItemSetHierarchy() throws {
        let ctx = makeContext()
        let plan = Plan(name: "PPL", order: 0)
        ctx.insert(plan)
        let workout = Workout(name: "Push Day", day: .mon, order: 0)
        workout.plan = plan
        ctx.insert(workout)
        let item = PlanItem(exId: "Barbell_Bench_Press", order: 0)
        item.workout = workout
        ctx.insert(item)
        for i in 0..<3 {
            let s = SetTemplate(weightKg: 60, reps: 10, rpe: 8, order: i)
            s.item = item
            ctx.insert(s)
        }
        try ctx.save()

        #expect(plan.workouts.count == 1)
        #expect(plan.exerciseCount == 1)
        #expect(workout.setCount == 3)
        #expect(plan.orderedWorkouts.first?.name == "Push Day")
    }

    @Test func cascadeDeleteRemovesSubtree() throws {
        let ctx = makeContext()
        let plan = Plan(name: "Temp", order: 0)
        ctx.insert(plan)
        let workout = Workout(name: "Day", day: .tue, order: 0)
        workout.plan = plan
        ctx.insert(workout)
        let item = PlanItem(exId: "X", order: 0)
        item.workout = workout
        ctx.insert(item)
        let set = SetTemplate(weightKg: 40, reps: 8, rpe: 7, order: 0)
        set.item = item
        ctx.insert(set)
        try ctx.save()

        ctx.delete(plan)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Plan>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Workout>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<PlanItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<SetTemplate>()).isEmpty)
    }

    @Test func renamePersists() throws {
        let ctx = makeContext()
        let plan = Plan(name: "Old", order: 0)
        ctx.insert(plan)
        try ctx.save()
        plan.name = "New"
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Plan>())
        #expect(fetched.first?.name == "New")
    }

    @Test func orderedWorkoutsRespectOrderField() {
        let ctx = makeContext()
        let plan = Plan(name: "P", order: 0)
        ctx.insert(plan)
        for (i, day) in [Weekday.fri, .mon, .wed].enumerated() {
            let w = Workout(name: day.short, day: day, order: 2 - i) // reversed order field
            w.plan = plan
            ctx.insert(w)
        }
        // order fields: Fri=2, Mon=1, Wed=0 -> ordered should be Wed, Mon, Fri.
        #expect(plan.orderedWorkouts.map(\.day) == [.wed, .mon, .fri])
    }

    @Test func userProfileAndSettingsAreSingletons() {
        let ctx = makeContext()
        let p1 = ctx.userProfile()
        let p2 = ctx.userProfile()
        #expect(p1.id == p2.id)

        let s1 = ctx.appSettings()
        s1.units = .lb
        let s2 = ctx.appSettings()
        #expect(s2.units == .lb)
    }

    @Test func historyFetchFiltersAndSortsByDate() throws {
        let ctx = makeContext()
        let now = Date()
        let older = HistoryEntry(exId: "A", date: now.addingTimeInterval(-1000), topW: 50, topR: 5, e1rm: 58, sets: [])
        let newer = HistoryEntry(exId: "A", date: now, topW: 60, topR: 5, e1rm: 70, sets: [])
        let other = HistoryEntry(exId: "B", date: now, topW: 40, topR: 5, e1rm: 46, sets: [])
        [older, newer, other].forEach { ctx.insert($0) }
        try ctx.save()

        let a = ctx.history(forExercise: "A")
        #expect(a.count == 2)
        #expect(a.map(\.e1rm) == [58, 70]) // sorted oldest -> newest
    }

    @Test func recordedSetsRoundTripThroughJSON() {
        let entry = HistoryEntry(exId: "A", date: Date(), topW: 90, topR: 8, e1rm: 114,
                                 sets: [RecordedSet(w: 90, r: 8), RecordedSet(w: 80, r: 10)])
        #expect(entry.sets.count == 2)
        #expect(entry.sets.first == RecordedSet(w: 90, r: 8))
    }

    @Test func materializesGeneratedPlan() throws {
        let ctx = makeContext()
        let generator = PlanGenerator(catalog: ExerciseCatalog(bundle: .main))
        var answers = QuizAnswers(); answers.daysPerWeek = 3
        let generated = generator.generate(answers)

        PlanFactory.insert(generated, into: ctx, order: 0)
        try ctx.save()

        let plans = try ctx.fetch(FetchDescriptor<Plan>())
        #expect(plans.count == 1)
        #expect(plans.first?.workouts.count == 3)
        #expect((plans.first?.exerciseCount ?? 0) > 0)
        // Every materialized item has at least one set.
        let items = try ctx.fetch(FetchDescriptor<PlanItem>())
        #expect(items.allSatisfy { !$0.sets.isEmpty })
    }

    @Test func addWorkoutPicksFreeWeekday() throws {
        let ctx = makeContext()
        let plan = Plan(name: "P", order: 0)
        ctx.insert(plan)
        let mon = Workout(name: "A", day: .mon, order: 0); mon.plan = plan; ctx.insert(mon)
        let wed = Workout(name: "B", day: .wed, order: 1); wed.plan = plan; ctx.insert(wed)

        let added = PlanFactory.addWorkout(to: plan, into: ctx)
        // Mon & Wed taken; next preferred free day is Fri.
        #expect(added.day == .fri)
    }
}
