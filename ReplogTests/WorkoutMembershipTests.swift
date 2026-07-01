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
