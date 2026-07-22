//
//  ReorderingTests.swift
//  ReplogTests
//
//  Drag-to-reorder: SwiftUI's `onMove` index math (including the drag-down
//  off-by-one), contiguous renumbering of `order`, and append-order allocation.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

struct ReorderingTests {

    @Test func draggingUpInsertsBeforeTheTargetRow() {
        #expect(Reordering.moved([0, 1, 2, 3], from: [2], to: 0) == [2, 0, 1, 3])
        #expect(Reordering.moved([0, 1, 2, 3], from: [3], to: 1) == [0, 3, 1, 2])
    }

    @Test func draggingDownAccountsForTheLiftedRow() {
        // SwiftUI's destination indexes the pre-move list, so it sits one past the slot.
        #expect(Reordering.moved([0, 1, 2, 3], from: [0], to: 3) == [1, 2, 0, 3])
        #expect(Reordering.moved([0, 1, 2, 3], from: [0], to: 4) == [1, 2, 3, 0])
    }

    @Test func multiRowDragKeepsTheDraggedRowsRelativeOrder() {
        #expect(Reordering.moved([0, 1, 2, 3], from: [0, 1], to: 4) == [2, 3, 0, 1])
        #expect(Reordering.moved([0, 1, 2, 3], from: [1, 3], to: 0) == [1, 3, 0, 2])
    }

    @Test func noOpAndOutOfRangeMovesReturnTheListUnchanged() {
        #expect(Reordering.moved([0, 1, 2], from: [1], to: 1) == [0, 1, 2])
        #expect(Reordering.moved([0, 1, 2], from: [1], to: 2) == [0, 1, 2])
        #expect(Reordering.moved([0, 1, 2], from: [], to: 0) == [0, 1, 2])
        #expect(Reordering.moved([0, 1, 2], from: [9], to: 0) == [0, 1, 2])
        #expect(Reordering.moved([Int](), from: [0], to: 0).isEmpty)
    }
}

@MainActor
struct ReorderingModelTests {
    private func makeContext() -> ModelContext { ModelContext(ReplogSchema.inMemoryContainer()) }

    /// A plan whose three workouts are already numbered 0, 1, 2.
    private func seedPlan(_ ctx: ModelContext) -> Plan {
        let plan = Plan(name: "PPL", order: 0); ctx.insert(plan)
        for (index, day) in [Weekday.mon, .wed, .fri].enumerated() {
            let w = Workout(name: day.short, day: day, order: index); w.plan = plan; ctx.insert(w)
        }
        try? ctx.save()
        return plan
    }

    @Test func movingTheLastWorkoutToTheTopRenumbersOrders() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx)

        #expect(Reordering.apply(from: IndexSet(integer: 2), to: 0, in: plan.orderedWorkouts))
        try ctx.save()

        #expect(plan.orderedWorkouts.map(\.name) == ["Fri", "Mon", "Wed"])
        #expect(plan.orderedWorkouts.map(\.order) == [0, 1, 2])
    }

    @Test func moveSurvivesARefetch() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx)

        Reordering.apply(from: IndexSet(integer: 0), to: 3, in: plan.orderedWorkouts)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<Plan>()).first)
        #expect(fetched.orderedWorkouts.map(\.name) == ["Wed", "Fri", "Mon"])
        #expect(fetched.orderedWorkouts.map(\.order) == [0, 1, 2])
    }

    @Test func dropInPlaceReportsNoChange() {
        let ctx = makeContext()
        let plan = seedPlan(ctx)
        #expect(!Reordering.apply(from: IndexSet(integer: 1), to: 1, in: plan.orderedWorkouts))
        #expect(plan.orderedWorkouts.map(\.name) == ["Mon", "Wed", "Fri"])
    }

    @Test func applyHealsDuplicateOrders() {
        let ctx = makeContext()
        let plan = seedPlan(ctx)
        plan.workouts.forEach { $0.order = 0 }                 // legacy data with colliding orders

        #expect(Reordering.apply(from: IndexSet(integer: 0), to: 0, in: plan.orderedWorkouts))
        #expect(plan.orderedWorkouts.map(\.order) == [0, 1, 2])
    }

    @Test func reorderingExercisesRenumbersPlanItems() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx)
        let workout = try #require(plan.orderedWorkouts.first)
        for exId in ["Bench", "Row", "Curl"] { PlanFactory.addExercise(exId, to: workout, into: ctx) }
        try ctx.save()

        Reordering.apply(from: IndexSet(integer: 2), to: 0, in: workout.orderedItems)
        try ctx.save()

        #expect(workout.orderedItems.map(\.exId) == ["Curl", "Bench", "Row"])
        #expect(workout.orderedItems.map(\.order) == [0, 1, 2])
    }

    @Test func nextOrderAppendsPastTheHighestOrderInUse() throws {
        let ctx = makeContext()
        let plan = seedPlan(ctx)
        #expect(Reordering.nextOrder(after: plan.workouts) == 3)

        // Deleting the middle workout leaves a gap; the next order must still be unique.
        ctx.delete(plan.orderedWorkouts[1])
        try ctx.save()
        #expect(Reordering.nextOrder(after: plan.workouts) == 3)
        #expect(Reordering.nextOrder(after: [Workout]()) == 0)
    }
}
