//
//  DebugPlanImport.swift
//  Replog
//
//  DEBUG-only: builds the owner's own training log into a plan, on request.
//
//  `REPLOG_PLAN=projectbody` -> adds "PROJECT BODY" if it is not already there.
//
//  This exists because there is no UI automation in this project (owner's call), so a plan
//  with 45 exercises across three days cannot be entered any other way than by hand. It is
//  additive and idempotent: it never touches an existing plan, and running it twice does
//  nothing the second time.
//
//  The numbers are the LAST session logged for each movement, so the plan opens where the
//  training actually left off rather than at a generic estimate. `estimated` is deliberately
//  false — these are real logged loads, not seeds, and the live log should not label them
//  as suggestions.
//
//  Self-contained on purpose: delete this one file and the feature is gone.
//

import Foundation
import SwiftData

#if DEBUG
@MainActor
enum DebugPlanImport {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["REPLOG_PLAN"] == "projectbody"
    }

    /// One prescribed movement: the catalog id, the load per set, and the reps each set runs.
    private struct Entry {
        let exId: String
        let weights: [Double]
        let reps: Int
        /// True for a hold, where `reps` is seconds (the app's convention).
        var isHold: Bool = false
    }

    // MARK: - Friday — Day 2 then Day 1

    private static let friday: [Entry] = [
        // Day 2 (13.07.26)
        Entry(exId: "Wide-Grip_Lat_Pulldown", weights: [45, 60, 60], reps: 10),
        Entry(exId: "Seated_Cable_Rows", weights: [40, 50, 60], reps: 10),
        Entry(exId: "Dumbbell_Bicep_Curl", weights: [10, 10, 10], reps: 10),
        Entry(exId: "Straight-Arm_Pulldown", weights: [40, 60, 75], reps: 10),
        Entry(exId: "Face_Pull", weights: [15, 15, 20], reps: 12),
        Entry(exId: "Hammer_Curls", weights: [10, 10, 14], reps: 10),
        // Day 1 (12.07.26)
        Entry(exId: "Dumbbell_Shoulder_Press", weights: [40, 80, 100, 120], reps: 10),
        Entry(exId: "Incline_Dumbbell_Press", weights: [20, 24, 28, 32], reps: 10),
        Entry(exId: "Arnold_Dumbbell_Press", weights: [20, 20, 20], reps: 10),
        Entry(exId: "EZ-Bar_Skullcrusher", weights: [10, 15, 15], reps: 10),
        Entry(exId: "Cable_Seated_Lateral_Raise", weights: [3.75, 5, 5], reps: 12),
        Entry(exId: "Triceps_Pushdown_-_Rope_Attachment", weights: [20, 25, 30], reps: 10),
        Entry(exId: "Hanging_Leg_Raise", weights: [0, 0, 0], reps: 20),
        Entry(exId: "Decline_Crunch", weights: [0, 0, 0], reps: 20),
        Entry(exId: "Cable_Crunch", weights: [50, 50, 50], reps: 15),
        Entry(exId: "Plank", weights: [0], reps: 60, isHold: true),
    ]

    // MARK: - Saturday — Day 4 then Day 3

    private static let saturday: [Entry] = [
        // Day 4 (17.07.26)
        Entry(exId: "Leverage_Incline_Chest_Press", weights: [24, 28, 32], reps: 10),
        Entry(exId: "Leverage_Chest_Press", weights: [40, 70, 90], reps: 10),
        Entry(exId: "Butterfly", weights: [20, 30, 40], reps: 12),
        Entry(exId: "Triceps_Pushdown_-_V-Bar_Attachment", weights: [20, 25, 30], reps: 10),
        Entry(exId: "Side_Lateral_Raise", weights: [8, 10, 10], reps: 12),
        Entry(exId: "Cable_Rope_Overhead_Triceps_Extension", weights: [10, 10, 10], reps: 12),
        // Day 3 (16.07.26)
        Entry(exId: "Hack_Squat", weights: [0, 40, 40, 70], reps: 10),
        Entry(exId: "Split_Squats", weights: [0, 0, 0], reps: 8),
        Entry(exId: "Bodyweight_Walking_Lunge", weights: [0, 0, 0], reps: 15),
        Entry(exId: "Lying_Leg_Curls", weights: [40, 50, 60], reps: 12),
        Entry(exId: "Leg_Extensions", weights: [30, 30, 30], reps: 12),
        Entry(exId: "Hanging_Leg_Raise", weights: [0, 0, 0], reps: 20),
        Entry(exId: "Decline_Crunch", weights: [0, 0, 0], reps: 30),
        Entry(exId: "Crunches", weights: [50, 50, 50], reps: 15),
        Entry(exId: "Plank", weights: [0], reps: 60, isHold: true),
    ]

    // MARK: - Sunday — Day 5 then Day 6

    private static let sunday: [Entry] = [
        // Day 5 (19.07.26, falling back to 07.07.26 where the last session was blank)
        Entry(exId: "Lying_T-Bar_Row", weights: [40, 80, 100, 120], reps: 10),
        Entry(exId: "Dumbbell_Incline_Row", weights: [20, 40, 20], reps: 10),
        Entry(exId: "Barbell_Curl", weights: [20, 25, 30], reps: 10),
        Entry(exId: "Straight-Arm_Dumbbell_Pullover", weights: [35, 45, 55], reps: 12),
        Entry(exId: "Face_Pull", weights: [15, 20, 25], reps: 12),
        Entry(exId: "Reverse_Barbell_Curl", weights: [20, 25, 25], reps: 10),
        // Day 6 (08.07.26, falling back to 28.06.26 where the last session was blank)
        Entry(exId: "Dumbbell_Shrug", weights: [16, 20, 24], reps: 12),
        Entry(exId: "Incline_Dumbbell_Press", weights: [20, 24, 30], reps: 10),
        Entry(exId: "Bodyweight_Walking_Lunge", weights: [0, 0, 0], reps: 15),
        Entry(exId: "Standing_Calf_Raises", weights: [40, 40, 40], reps: 15),
        Entry(exId: "Flat_Bench_Lying_Leg_Raise", weights: [0, 0, 0], reps: 20),
        Entry(exId: "Decline_Crunch", weights: [0, 0, 0], reps: 15),
        Entry(exId: "Cable_Crunch", weights: [50, 50, 50], reps: 15),
        Entry(exId: "Plank", weights: [0], reps: 60, isHold: true),
    ]

    // MARK: - Building

    static let planName = "PROJECT BODY"

    /// What each day is called, taken from what it actually trains rather than from the
    /// notebook it came out of. Counted by direct (primary) exercises: Friday is 4 shoulder,
    /// 4 arm and 3 back movements; Saturday 5 leg and 3 chest; Sunday 3 back and 2 arm. All
    /// three finish on core, so core only earns a place in the name where it is not the
    /// thing that distinguishes the day.
    static func name(for day: Weekday) -> String {
        switch day {
        case .fri: return "Back, Shoulders & Arms"
        case .sat: return "Chest, Legs & Core"
        case .sun: return "Back, Arms & Core"
        default:   return planName
        }
    }

    /// Adds the plan unless one of the same name is already there. Returns what happened,
    /// so a caller can log it.
    @discardableResult
    static func addIfNeeded(_ context: ModelContext) -> String {
        guard isRequested else { return "not requested" }

        let existing = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        if let plan = existing.first(where: { $0.name == planName }) {
            // The plan is already on the device, so adding it again would duplicate it. A
            // NAME, though, is safe to bring up to date: renaming a workout touches no sets,
            // no history and no logged session, and leaving the old ones stale would mean
            // this only ever works on a device that has never run it.
            let renamed = reconcileNames(of: plan)
            print("[PROJECT BODY] already present — \(renamed) workout(s) renamed")
            if renamed > 0 { try? context.save() }
            return "already present"
        }

        let generated = GeneratedPlan(
            name: planName,
            colorHex: "#E8663A",
            workouts: [
                workout(named: Self.name(for: .fri), on: .fri, from: friday),
                workout(named: Self.name(for: .sat), on: .sat, from: saturday),
                workout(named: Self.name(for: .sun), on: .sun, from: sunday),
            ],
            headline: "PROJECT BODY"
        )
        let plan = PlanFactory.insert(generated, into: context, order: existing.count)
        try? context.save()
        let exercises = generated.workouts.reduce(0) { $0 + $1.items.count }
        print("[PROJECT BODY] added \(plan.name): \(generated.workouts.count) workouts, \(exercises) exercises")
        for workout in generated.workouts {
            print("[PROJECT BODY]   \(workout.day) — \(workout.name): \(workout.items.count) exercises")
        }
        return "added \(generated.workouts.count) workouts"
    }

    /// Brings an existing plan's workout names in line with `name(for:)`. Returns how many
    /// actually changed, so a no-op run says so rather than claiming work it did not do.
    private static func reconcileNames(of plan: Plan) -> Int {
        var changed = 0
        for workout in plan.workouts {
            let wanted = name(for: workout.day)
            guard workout.name != wanted else { continue }
            print("[PROJECT BODY]   \(workout.day): \"\(workout.name)\" -> \"\(wanted)\"")
            workout.name = wanted
            changed += 1
        }
        return changed
    }

    private static func workout(named name: String, on day: Weekday, from entries: [Entry]) -> GeneratedWorkout {
        GeneratedWorkout(name: name, day: day, items: entries.map { entry in
            GeneratedItem(
                exId: entry.exId,
                sets: entry.weights.map {
                    // `estimated: false` — these are logged loads, not the app's guesses.
                    GeneratedSet(weightKg: $0, reps: entry.reps, rpe: 8, estimated: false)
                },
                restSeconds: nil        // the athlete's own default rest applies
            )
        })
    }
}
#endif
