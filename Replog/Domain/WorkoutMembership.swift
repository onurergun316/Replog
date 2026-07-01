//
//  WorkoutMembership.swift
//  Replog
//
//  Answers "which of the user's workouts already contain this exercise?" — used by the
//  Library → plan add flow (the exercise detail's "In your workouts" section and the
//  add-to-workout picker). Pure & testable.
//

import Foundation

enum WorkoutMembership {
    /// Every workout across `plans` whose items include `exId`, in plan/workout order.
    static func workouts(containing exId: String, in plans: [Plan]) -> [Workout] {
        plans.flatMap(\.orderedWorkouts).filter { workout in
            workout.items.contains { $0.exId == exId }
        }
    }

    /// Whether `workout` already contains `exId`.
    static func contains(_ exId: String, in workout: Workout) -> Bool {
        workout.items.contains { $0.exId == exId }
    }
}
