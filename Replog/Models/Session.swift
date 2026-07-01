//
//  Session.swift
//  Replog
//
//  Live workout logging models. An ActiveSession is created from a Workout's
//  prescribed sets and persisted so an in-progress workout survives relaunch.
//

import Foundation
import SwiftData

@Model
final class ActiveSession {
    var id: UUID = UUID()
    var workoutId: UUID?
    var name: String = ""
    var planName: String = ""
    var startedAt: Date = Date()
    /// Whether the live session is currently presented. Closing with "X" sets this
    /// false (paused & persisted) so the workout survives and can be continued; it is
    /// only deleted on Finish.
    var isOpen: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []

    init(workoutId: UUID?, name: String, planName: String, startedAt: Date = Date()) {
        self.workoutId = workoutId
        self.name = name
        self.planName = planName
        self.startedAt = startedAt
    }

    /// Exercises ordered with finished ones (positive doneOrder) pushed to the bottom.
    var orderedExercises: [SessionExercise] {
        exercises.sorted { a, b in
            switch (a.isDone, b.isDone) {
            case (false, true): return true
            case (true, false): return false
            case (true, true):  return a.doneOrder < b.doneOrder
            case (false, false): return a.order < b.order
            }
        }
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var completedSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var isComplete: Bool { totalSets > 0 && completedSets == totalSets }
}

@Model
final class SessionExercise {
    var id: UUID = UUID()
    var exId: String = ""
    var order: Int = 0
    /// Monotonic counter set when the exercise becomes fully done (drives reorder). -1 = not done.
    var doneOrder: Int = -1
    /// Rest between sets for this exercise, in seconds. `nil` = use the app default.
    /// Copied from the plan's `PlanItem.restSeconds` when the session is built.
    var restSeconds: Int?
    var session: ActiveSession?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var sets: [LoggedSet] = []

    init(exId: String, order: Int = 0) {
        self.exId = exId
        self.order = order
    }

    var orderedSets: [LoggedSet] { sets.sorted { $0.order < $1.order } }
    var isDone: Bool { !sets.isEmpty && sets.allSatisfy(\.done) }

    /// The heaviest set by estimated 1RM (used for history & "best").
    var topSet: LoggedSet? {
        sets.max { Formulas.e1rm(kg: $0.weightKg, reps: $0.reps) < Formulas.e1rm(kg: $1.weightKg, reps: $1.reps) }
    }
}

@Model
final class LoggedSet {
    var id: UUID = UUID()
    var weightKg: Double = 20
    var reps: Int = 10
    var rpe: Int = 8
    var done: Bool = false
    /// Same set index's weight/reps from the previous session (drives trend arrows).
    var prevWeight: Double?
    var prevReps: Int?
    var order: Int = 0
    var exercise: SessionExercise?

    init(weightKg: Double, reps: Int, rpe: Int, prevWeight: Double? = nil, prevReps: Int? = nil, order: Int = 0) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.prevWeight = prevWeight
        self.prevReps = prevReps
        self.order = order
    }

    var weightTrend: Trend { TrendCalculator.trend(current: weightKg, previous: prevWeight) }
    var repsTrend: Trend { TrendCalculator.trend(current: Double(reps), previous: prevReps.map(Double.init)) }
}
