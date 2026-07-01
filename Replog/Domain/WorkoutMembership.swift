//
//  WorkoutMembership.swift
//  Replog
//
//  Answers "which of the user's workouts already contain this exercise?" — used by the
//  Library → plan add flow (the exercise detail's "In your workouts" section and the
//  add-to-workout picker). Pure & testable.
//

import Foundation

/// A plan and the subset of its workouts that contain a given exercise.
struct PlanWorkouts: Identifiable {
    let plan: Plan
    let workouts: [Workout]
    var id: UUID { plan.id }
}

enum WorkoutMembership {
    /// Every workout across `plans` whose items include `exId`, in plan/workout order.
    static func workouts(containing exId: String, in plans: [Plan]) -> [Workout] {
        plans.flatMap(\.orderedWorkouts).filter { workout in
            workout.items.contains { $0.exId == exId }
        }
    }

    /// Matching workouts grouped by their plan (plan order preserved). Only plans with at
    /// least one matching workout are returned — so the UI can label each group with its
    /// plan and disambiguate similarly-named workouts across plans.
    static func grouped(containing exId: String, in plans: [Plan]) -> [PlanWorkouts] {
        plans.compactMap { plan in
            let matching = plan.orderedWorkouts.filter { contains(exId, in: $0) }
            return matching.isEmpty ? nil : PlanWorkouts(plan: plan, workouts: matching)
        }
    }

    /// Whether `workout` already contains `exId`.
    static func contains(_ exId: String, in workout: Workout) -> Bool {
        workout.items.contains { $0.exId == exId }
    }
}
