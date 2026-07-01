//
//  WorkoutMembershipTests.swift
//  ReplogTests
//
//  "Which workouts contain this exercise?" + add/remove round-trips used by the
//  Library → plan add flow.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct WorkoutMembershipTests {
    private func makeContext() -> ModelContext { ModelContext(ReplogSchema.inMemoryContainer()) }

    private func seedPlan(_ ctx: ModelContext) -> (Plan, Workout, Workout) {
        let plan = Plan(name: "P", order: 0); ctx.insert(plan)
        let a = Workout(name: "A", day: .mon, order: 0); a.plan = plan; ctx.insert(a)
        let b = Workout(name: "B", day: .tue, order: 1); b.plan = plan; ctx.insert(b)
        return (plan, a, b)
    }

    @Test func findsWorkoutsContainingExercise() throws {
        let ctx = makeContext()
        let (plan, a, b) = seedPlan(ctx)
        PlanFactory.addExercise("Bench", to: a, into: ctx)
        PlanFactory.addExercise("Squat", to: b, into: ctx)
        try ctx.save()

        #expect(WorkoutMembership.workouts(containing: "Bench", in: [plan]).map(\.name) == ["A"])
        #expect(WorkoutMembership.contains("Bench", in: a))
        #expect(!WorkoutMembership.contains("Bench", in: b))
    }

    @Test func groupedByPlanKeepsOnlyMatchingPlans() throws {
        let ctx = makeContext()
        let p1 = Plan(name: "PPL", order: 0); ctx.insert(p1)
        let a = Workout(name: "Push", day: .mon, order: 0); a.plan = p1; ctx.insert(a)
        let b = Workout(name: "Pull", day: .tue, order: 1); b.plan = p1; ctx.insert(b)
        let p2 = Plan(name: "Empty", order: 1); ctx.insert(p2)
        let c = Workout(name: "Legs", day: .wed, order: 0); c.plan = p2; ctx.insert(c)
        PlanFactory.addExercise("Bench", to: a, into: ctx)
        PlanFactory.addExercise("Bench", to: b, into: ctx)   // p1 has it twice
        try ctx.save()

        let groups = WorkoutMembership.grouped(containing: "Bench", in: [p1, p2])
        #expect(groups.count == 1)                            // p2 excluded (no match)
        #expect(groups.first?.plan.name == "PPL")
        #expect(groups.first?.workouts.map(\.name) == ["Push", "Pull"])
    }

    @Test func noneWhenExerciseIsAbsent() throws {
        let ctx = makeContext()
        let (plan, _, _) = seedPlan(ctx)
        try ctx.save()
        #expect(WorkoutMembership.workouts(containing: "Nope", in: [plan]).isEmpty)
    }

    @Test func addThenRemoveRoundTrips() throws {
        let ctx = makeContext()
        let (_, a, _) = seedPlan(ctx)

        PlanFactory.addExercise("Bench", to: a, into: ctx); try ctx.save()
        #expect(WorkoutMembership.contains("Bench", in: a))
        #expect(a.items.first { $0.exId == "Bench" }?.sets.count == 3)   // default prescription

        let removed = PlanFactory.removeExercise("Bench", from: a, into: ctx); try ctx.save()
        #expect(removed)
        #expect(!WorkoutMembership.contains("Bench", in: a))

        // Removing again is a no-op and reports nothing removed.
        #expect(!PlanFactory.removeExercise("Bench", from: a, into: ctx))
    }
}
