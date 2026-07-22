//
//  PlanFactory.swift
//  Replog
//
//  Materializes a pure GeneratedPlan into SwiftData models, and creates empty
//  plans/workouts for the "Build your own" path.
//

import Foundation
import SwiftData

@MainActor
enum PlanFactory {

    /// Inserts a generated plan (and its full subtree) into the context. Returns the Plan.
    /// Pass the AI coach report markdown to save it on the plan (re-readable in Profile).
    @discardableResult
    static func insert(_ gen: GeneratedPlan, into context: ModelContext, order: Int,
                       reportMarkdown: String = "") -> Plan {
        let plan = Plan(name: gen.name, colorHex: gen.colorHex, order: order)
        plan.headline = gen.headline
        plan.reportMarkdown = reportMarkdown
        plan.programId = gen.programId ?? ""
        if let p = gen.progression {
            plan.progressionType = p.type
            plan.progressionRule = p.rule
            plan.progressionDeload = p.deload
        }
        context.insert(plan)

        for (wIndex, gw) in gen.workouts.enumerated() {
            let workout = Workout(name: gw.name, day: gw.day, order: wIndex)
            workout.plan = plan
            context.insert(workout)

            for (iIndex, gi) in gw.items.enumerated() {
                let item = PlanItem(exId: gi.exId, order: iIndex)
                item.restSeconds = gi.restSeconds
                item.workout = workout
                context.insert(item)

                for (sIndex, gs) in gi.sets.enumerated() {
                    let set = SetTemplate(weightKg: gs.weightKg, reps: gs.reps, rpe: gs.rpe,
                                          order: sIndex, estimated: gs.estimated)
                    set.item = item
                    context.insert(set)
                }
            }
        }
        return plan
    }

    /// Creates an empty plan for manual building.
    @discardableResult
    static func emptyPlan(name: String = "New Plan", into context: ModelContext, order: Int) -> Plan {
        let plan = Plan(name: name, colorHex: "#FF6A3D", order: order)
        context.insert(plan)
        return plan
    }

    /// Adds a new empty workout to a plan on its first free weekday. When all seven
    /// weekdays are taken, the new workout becomes a day-less "Extra" instead of
    /// silently doubling up a day.
    @discardableResult
    static func addWorkout(to plan: Plan, into context: ModelContext) -> Workout {
        let used = Set(plan.workouts.filter { !$0.isExtra }.map(\.day))
        let day = WeekdayPlanner.firstFreeDay(excluding: used)
        let workout = Workout(name: "New Day", day: day ?? .sun,
                              order: Reordering.nextOrder(after: plan.workouts))
        workout.isExtra = day == nil
        workout.plan = plan
        context.insert(workout)
        return workout
    }

    /// Adds a default 3-set prescription for an exercise to a workout.
    @discardableResult
    static func addExercise(_ exId: String, to workout: Workout, into context: ModelContext) -> PlanItem {
        let item = PlanItem(exId: exId, order: Reordering.nextOrder(after: workout.items))
        item.workout = workout
        context.insert(item)
        for i in 0..<3 {
            let set = SetTemplate(weightKg: 20, reps: 10, rpe: 8, order: i)
            set.item = item
            context.insert(set)
        }
        return item
    }

    /// Removes every occurrence of `exId` from a workout. Returns whether anything was removed.
    @discardableResult
    static func removeExercise(_ exId: String, from workout: Workout, into context: ModelContext) -> Bool {
        let matches = workout.items.filter { $0.exId == exId }
        matches.forEach { context.delete($0) }
        return !matches.isEmpty
    }
}
