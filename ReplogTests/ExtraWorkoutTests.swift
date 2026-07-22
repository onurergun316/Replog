//
//  ExtraWorkoutTests.swift
//  ReplogTests
//
//  "Extra" workouts: day-less training days the user can run any time. They persist,
//  label themselves, and stay out of the weekly schedule.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct ExtraWorkoutTests {
    private func makeContext() -> ModelContext { ModelContext(ReplogSchema.inMemoryContainer()) }

    @Test func isExtraDefaultsFalseAndRoundTrips() throws {
        let ctx = makeContext()
        let plan = Plan(name: "P", order: 0); ctx.insert(plan)
        let normal = Workout(name: "Push", day: .mon, order: 0); normal.plan = plan; ctx.insert(normal)
        let extra = Workout(name: "Bonus", day: .mon, order: 1); extra.isExtra = true
        extra.plan = plan; ctx.insert(extra)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Plan>()).first)
        let workouts = fetched.orderedWorkouts
        #expect(workouts.map(\.isExtra) == [false, true])
        #expect(workouts.map(\.slotLabel) == ["Mon", "Extra"])
        #expect(workouts.map(\.slotTag) == ["MON", "EXTRA"])
    }

    @Test func extrasStayOutOfTheSchedule() throws {
        let ctx = makeContext()
        let plan = Plan(name: "P", order: 0); ctx.insert(plan)
        let mon = Workout(name: "Push", day: .mon, order: 0); mon.plan = plan; ctx.insert(mon)
        let extra = Workout(name: "Bonus", day: .fri, order: 1); extra.isExtra = true
        extra.plan = plan; ctx.insert(extra)
        try ctx.save()

        // The extra's leftover `day` (.fri) must not leak into any schedule derivation.
        #expect(StreakEngine.scheduledDays(in: [plan]) == [.mon])
        #expect(plan.scheduledDays == [.mon])
        #expect(plan.hasExtras)
    }

    @Test func eighthWorkoutBecomesAnExtra() throws {
        let ctx = makeContext()
        let plan = Plan(name: "Full", order: 0); ctx.insert(plan)
        for _ in 0..<7 { PlanFactory.addWorkout(to: plan, into: ctx) }
        try ctx.save()

        #expect(Set(plan.workouts.filter { !$0.isExtra }.map(\.day)).count == 7)
        #expect(plan.workouts.allSatisfy { !$0.isExtra })

        let eighth = PlanFactory.addWorkout(to: plan, into: ctx)
        try ctx.save()
        #expect(eighth.isExtra)
        // And a ninth is another extra — extras never consume a weekday.
        #expect(PlanFactory.addWorkout(to: plan, into: ctx).isExtra)
    }
}
