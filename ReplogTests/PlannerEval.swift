//
//  PlannerEval.swift
//  ReplogTests
//
//  The planner evaluation harness: synthetic athlete personas (goal, equipment,
//  injuries, and a fabricated `HistoryEntry` trail) plus pure metric helpers that
//  measure a generated plan's PROPERTIES — the things a good program must always
//  satisfy regardless of which specific exercises the engine picks.
//
//  Why a harness and not one-off asserts: the plan is non-deterministic on-device
//  (the live model) and deterministic in the simulator (the `PlanGenerator`
//  fallback). Asserting *properties* rather than exact plans lets the same tests
//  guard both paths. See `PlannerEvalTests` for the assertions and the documented
//  fallback caveat (`FoundationModels` is unavailable in the simulator, so these
//  runs exercise the deterministic engine; the live path is verified on device).
//

import Foundation
@testable import Replog

// MARK: - Personas

/// A synthetic user: their onboarding intake plus a fabricated logged-training trail.
struct EvalPersona {
    var name: String
    var answers: QuizAnswers
    /// Recent logged training. Empty models a fresh onboarding.
    var history: [HistoryEntry]
}

/// Builds the persona roster from the real catalog so exIds resolve and equipment
/// filters behave exactly as in production. `@MainActor` because `HistoryEntry` is a
/// `@Model` (MainActor-isolated under the project's default actor isolation).
@MainActor
enum EvalPersonas {

    /// A monotonically progressing history for one exercise (e1RM climbs each session).
    static func progressing(exId: String, now: Date, sessions: Int = 4,
                            startKg: Double = 60, stepKg: Double = 2.5, reps: Int = 8,
                            sets: Int = 4) -> [HistoryEntry] {
        (0..<sessions).map { i in
            let w = startKg + Double(i) * stepKg
            return HistoryEntry(exId: exId,
                                date: now.addingTimeInterval(-Double(sessions - i) * 7 * 86_400),
                                topW: w, topR: reps,
                                e1rm: Formulas.e1rmRounded(kg: w, reps: reps),
                                sets: Array(repeating: RecordedSet(w: w, r: reps), count: sets))
        }
    }

    /// A stalled history: same top set every session (e1RM flat).
    static func stalling(exId: String, now: Date, sessions: Int = 4,
                        kg: Double = 80, reps: Int = 6, sets: Int = 4) -> [HistoryEntry] {
        (0..<sessions).map { i in
            HistoryEntry(exId: exId,
                         date: now.addingTimeInterval(-Double(sessions - i) * 7 * 86_400),
                         topW: kg, topR: reps,
                         e1rm: Formulas.e1rmRounded(kg: kg, reps: reps),
                         sets: Array(repeating: RecordedSet(w: kg, r: reps), count: sets))
        }
    }

    /// The full roster used by the eval suite. Six+ distinct personas spanning goals,
    /// equipment access, injuries, experience, and history states.
    static func all(catalog: ExerciseCatalog, now: Date) -> [EvalPersona] {
        // Real exIds for history trails (primary movers so digests attribute correctly).
        func firstExId(_ muscle: Muscle) -> String {
            catalog.exercises(forMuscle: muscle).first { $0.primaryMuscles.contains(muscle) }?.id ?? ""
        }
        let chestId = firstExId(.chest)
        let quadId = firstExId(.quadriceps)
        let backId = firstExId(.lats)

        // 1) Fresh beginner, full gym, no history.
        var freshBeginner = QuizAnswers()
        freshBeginner.goal = .buildMuscle
        freshBeginner.experience = .beginner
        freshBeginner.daysPerWeek = 3
        freshBeginner.minutesPerSession = 45

        // 2) Intermediate hypertrophy, full gym, bench + squat progressing.
        var progressingLifter = QuizAnswers()
        progressingLifter.goal = .buildMuscle
        progressingLifter.experience = .intermediate
        progressingLifter.daysPerWeek = 4
        progressingLifter.minutesPerSession = 60

        // 3) Machine-only lifter — must never receive a non-machine (esp. bodyweight) movement.
        var machineOnly = QuizAnswers()
        machineOnly.goal = .recomp
        machineOnly.experience = .intermediate
        machineOnly.daysPerWeek = 4
        machineOnly.minutesPerSession = 50
        machineOnly.equipmentTypes = [.machine]

        // 4) Bodyweight-only (calisthenics) — only bodyOnly / bands may appear.
        var bodyweight = QuizAnswers()
        bodyweight.goal = .loseWeight
        bodyweight.experience = .beginner
        bodyweight.daysPerWeek = 3
        bodyweight.minutesPerSession = 40
        bodyweight.equipment = .bodyweight

        // 5) Knee-injured runner (sport) — quads/hams/calves must not be loaded as primaries.
        var injuredRunner = QuizAnswers()
        injuredRunner.goal = .sport
        injuredRunner.sport = .running
        injuredRunner.experience = .intermediate
        injuredRunner.daysPerWeek = 3
        injuredRunner.minutesPerSession = 45
        injuredRunner.injuries = [.knee]

        // 6) Fat-loss, home dumbbells, stalling — history shows a plateau.
        var stallingHomeUser = QuizAnswers()
        stallingHomeUser.goal = .loseWeight
        stallingHomeUser.experience = .intermediate
        stallingHomeUser.daysPerWeek = 4
        stallingHomeUser.minutesPerSession = 45
        stallingHomeUser.equipment = .home

        // 7) Advanced recomp, full gym, high frequency, mixed history.
        var advanced = QuizAnswers()
        advanced.goal = .recomp
        advanced.experience = .advanced
        advanced.daysPerWeek = 6
        advanced.minutesPerSession = 60

        return [
            EvalPersona(name: "Fresh beginner (no history)", answers: freshBeginner, history: []),
            EvalPersona(name: "Intermediate, bench+squat progressing", answers: progressingLifter,
                        history: progressing(exId: chestId, now: now)
                               + progressing(exId: quadId, now: now, startKg: 80, stepKg: 5, reps: 6)),
            EvalPersona(name: "Machine-only lifter", answers: machineOnly, history: []),
            EvalPersona(name: "Bodyweight-only", answers: bodyweight, history: []),
            EvalPersona(name: "Knee-injured runner", answers: injuredRunner, history: []),
            EvalPersona(name: "Fat-loss, home dumbbells, stalling", answers: stallingHomeUser,
                        history: stalling(exId: chestId, now: now)),
            EvalPersona(name: "Advanced recomp, high frequency", answers: advanced,
                        history: progressing(exId: backId, now: now)
                               + stalling(exId: quadId, now: now)),
        ]
    }
}

// MARK: - Metrics (pure measurement of a generated plan)

/// Pure functions that turn a `GeneratedPlan` into the numbers the property assertions
/// check. Kept separate from the assertions so both the deterministic and (future) live
/// paths can be measured the same way.
@MainActor
enum PlannerEvalMetrics {

    /// Every catalog exercise referenced by the plan (skips any exId that doesn't resolve).
    static func exercises(in plan: GeneratedPlan, catalog: ExerciseCatalog) -> [Exercise] {
        plan.workouts.flatMap(\.items).compactMap { catalog.exercise(id: $0.exId) }
    }

    /// The equipment the plan actually calls for. Missing equipment counts as bodyweight —
    /// the same rule the generator uses — so a machine-only plan must never surface `.bodyOnly`.
    static func equipmentUsed(in plan: GeneratedPlan, catalog: ExerciseCatalog) -> Set<Equipment> {
        Set(exercises(in: plan, catalog: catalog).map { $0.equipment ?? .bodyOnly })
    }

    /// The set of muscles the plan trains as PRIMARY movers.
    static func primaryMusclesTrained(in plan: GeneratedPlan, catalog: ExerciseCatalog) -> Set<Muscle> {
        Set(exercises(in: plan, catalog: catalog).flatMap(\.primaryMuscles))
    }

    /// Weekly working sets credited to each PRIMARY muscle (an exercise's sets count toward
    /// every primary mover it trains). This is the volume a coach programs against.
    static func weeklySetsPerMuscle(in plan: GeneratedPlan, catalog: ExerciseCatalog) -> [Muscle: Int] {
        var sets: [Muscle: Int] = [:]
        for item in plan.workouts.flatMap(\.items) {
            guard let ex = catalog.exercise(id: item.exId) else { continue }
            for muscle in ex.primaryMuscles { sets[muscle, default: 0] += item.sets.count }
        }
        return sets
    }

    /// Every prescribed rep count across the plan (should be uniform for the goal).
    static func prescribedReps(in plan: GeneratedPlan) -> Set<Int> {
        Set(plan.workouts.flatMap(\.items).flatMap(\.sets).map(\.reps))
    }

    /// Every prescribed RPE across the plan (should be uniform for the experience level).
    static func prescribedRPE(in plan: GeneratedPlan) -> Set<Int> {
        Set(plan.workouts.flatMap(\.items).flatMap(\.sets).map(\.rpe))
    }
}

// MARK: - Goal / experience prescription reference

/// The expected uniform prescription the deterministic engine emits, mirrored here so the
/// eval asserts the contract rather than re-deriving it. (When B-series makes prescription
/// history-aware, these become bands rather than exact values — see BACKLOG.)
enum EvalPrescription {
    static func reps(for goal: Goal) -> Int {
        switch goal {
        case .buildMuscle, .recomp: return 10
        case .loseWeight: return 13
        case .sport: return 8
        }
    }

    static func rpe(for experience: Experience) -> Int {
        switch experience {
        case .beginner: return 7
        case .intermediate: return 8
        case .advanced: return 9
        }
    }

    /// Evidence-based weekly-set guardrails per trained muscle: below `minEffective` is too
    /// little stimulus to justify programming the muscle; above `maxRecoverable` risks junk
    /// volume. The deterministic engine must land every trained muscle inside this band.
    static let minEffectiveSets = 2
    static let maxRecoverableSets = 40
}
