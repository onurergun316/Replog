//
//  UserData.swift
//  Replog
//
//  SwiftData models for the core "onion": Plan -> Workout -> PlanItem -> SetTemplate.
//  Cascade delete rules mean removing a plan removes its whole subtree.
//

import Foundation
import SwiftData

@Model
final class Plan {
    var id: UUID = UUID()
    var name: String = ""
    /// Accent dot color for the plan (hex). Cycles through a small palette by default.
    var colorHex: String = "#FF6A3D"
    var order: Int = 0
    var createdAt: Date = Date()
    /// The AI coach's saved report explaining the science behind this plan (markdown).
    /// Empty for manually-built plans. Re-readable from the Profile tab.
    var reportMarkdown: String = ""
    /// Display headline from generation, e.g. "Your Hypertrophy Plan".
    var headline: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Workout.plan)
    var workouts: [Workout] = []

    init(name: String, colorHex: String = "#FF6A3D", order: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.createdAt = Date()
    }

    /// Whether this plan has a saved AI coach report.
    var hasReport: Bool { !reportMarkdown.isEmpty }

    /// Workouts in display order.
    var orderedWorkouts: [Workout] { workouts.sorted { $0.order < $1.order } }

    /// Total prescribed exercises across all workouts.
    var exerciseCount: Int { workouts.reduce(0) { $0 + $1.items.count } }

    /// Distinct scheduled weekdays, in week order.
    var scheduledDays: [Weekday] {
        let days = Set(workouts.map(\.day))
        return Weekday.allCases.filter { days.contains($0) }
    }
}

@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    /// Stored as `Weekday.rawValue`; use `day` for typed access.
    var dayRaw: String = Weekday.mon.rawValue
    var order: Int = 0
    var plan: Plan?

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.workout)
    var items: [PlanItem] = []

    init(name: String, day: Weekday, order: Int = 0) {
        self.name = name
        self.dayRaw = day.rawValue
        self.order = order
    }

    var day: Weekday {
        get { Weekday(rawValue: dayRaw) ?? .mon }
        set { dayRaw = newValue.rawValue }
    }

    var orderedItems: [PlanItem] { items.sorted { $0.order < $1.order } }
    var setCount: Int { items.reduce(0) { $0 + $1.sets.count } }
}

@Model
final class PlanItem {
    var id: UUID = UUID()
    /// References `Exercise.id` in the static catalog.
    var exId: String = ""
    var order: Int = 0
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetTemplate.item)
    var sets: [SetTemplate] = []

    init(exId: String, order: Int = 0) {
        self.exId = exId
        self.order = order
    }

    var orderedSets: [SetTemplate] { sets.sorted { $0.order < $1.order } }
}

@Model
final class SetTemplate {
    var id: UUID = UUID()
    var weightKg: Double = 20
    var reps: Int = 10
    var rpe: Int = 8
    var order: Int = 0
    var item: PlanItem?

    init(weightKg: Double, reps: Int, rpe: Int, order: Int = 0) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.order = order
    }
}
