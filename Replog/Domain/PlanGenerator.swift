//
//  PlanGenerator.swift
//  Replog
//
//  The on-device "AI": a deterministic engine that builds a training Plan from the
//  onboarding answers using the real exercise catalog. Same input -> same plan.
//  (The UI shows a ~1.8s "Building your plan" spinner over this work.)
//

import Foundation

// MARK: - Output (pure value types, no SwiftData)

struct GeneratedSet: Equatable, Sendable {
    var weightKg: Double
    var reps: Int
    var rpe: Int
}

struct GeneratedItem: Equatable, Sendable {
    var exId: String
    var sets: [GeneratedSet]
    /// Per-exercise rest in seconds, carried from a program slot when present. `nil` = app default.
    var restSeconds: Int? = nil
}

struct GeneratedWorkout: Equatable, Sendable {
    var name: String
    var day: Weekday
    var items: [GeneratedItem]
}

/// A plan's progression metadata, copied from the chosen program so the coach (Phase 4) and
/// reports (Phase 6) can reason about how loads advance and when to deload.
struct PlanProgressionMeta: Equatable, Sendable {
    var type: String
    var rule: String
    var deload: String
}

struct GeneratedPlan: Equatable, Sendable {
    var name: String
    var colorHex: String
    var workouts: [GeneratedWorkout]
    /// Display header on the result screen, e.g. "Your Hypertrophy Plan".
    var headline: String
    /// The library program this plan was built from, when program-driven. `nil` for the
    /// legacy split-based generator path.
    var programId: String? = nil
    /// Progression rules from the chosen program, when program-driven.
    var progression: PlanProgressionMeta? = nil
}

// MARK: - Generator

struct PlanGenerator {
    let catalog: ExerciseCatalog

    nonisolated init(catalog: ExerciseCatalog = .shared) {
        self.catalog = catalog
    }

    /// Builds a complete plan for the given answers. Deterministic.
    func generate(_ answers: QuizAnswers) -> GeneratedPlan {
        let split = Split.choose(forDays: answers.daysPerWeek)
        let days = Self.weekdays(count: split.dayTemplates.count)
        let perWorkout = exercisesPerWorkout(minutes: answers.minutesPerSession)
        let allowed = answers.allowedEquipment
        let avoid = answers.avoidedMuscles
        let priority = priorityMuscles(answers)

        var workouts: [GeneratedWorkout] = []
        for (index, template) in split.dayTemplates.enumerated() {
            let items = buildItems(
                for: template,
                priority: priority,
                count: perWorkout,
                allowedEquipment: allowed,
                avoidMuscles: avoid,
                answers: answers
            )
            workouts.append(GeneratedWorkout(name: template.name, day: days[index], items: items))
        }

        return GeneratedPlan(
            name: split.planName,
            colorHex: Self.planColor(for: answers.goal),
            workouts: workouts,
            headline: headline(for: answers.goal)
        )
    }

    // MARK: Exercise selection

    /// Selects real catalog exercises for an arbitrary set of target muscles, honoring the
    /// user's equipment/injury constraints. Used by the AI resolver to map a blueprint's
    /// per-day muscle targets onto valid catalog exercises (guaranteeing images/refs exist).
    func selectItems(targetMuscles: [Muscle], count: Int, answers: QuizAnswers) -> [GeneratedItem] {
        let muscles = targetMuscles.isEmpty ? priorityMuscles(answers) : targetMuscles
        let template = DayTemplate(name: "", muscles: muscles)
        return buildItems(
            for: template,
            priority: priorityMuscles(answers),
            count: max(1, count),
            allowedEquipment: answers.allowedEquipment,
            avoidMuscles: answers.avoidedMuscles,
            answers: answers
        )
    }

    /// Real catalog exercises the AI can choose from for a day's target muscles, honoring the
    /// user's equipment/injury constraints. Interleaves across muscles for balance and ranks
    /// compound-first; capped at `limit`. The model picks from (and justifies) this list.
    func candidates(forMuscles muscles: [Muscle], answers: QuizAnswers, limit: Int = 14) -> [Exercise] {
        let allowed = answers.allowedEquipment
        let avoid = answers.avoidedMuscles
        let target = muscles.isEmpty ? priorityMuscles(answers) : muscles

        var perMuscle: [[Exercise]] = target.map { muscle in
            catalog.exercises(forMuscle: muscle)
                .filter { ex in
                    guard ex.primaryMuscles.contains(muscle) else { return false }
                    // Missing equipment counts as bodyweight, so a machine-only user never
                    // gets a bodyweight exercise slipped in.
                    if !allowed.contains(ex.equipment ?? .bodyOnly) { return false }
                    if !avoid.isEmpty, ex.primaryMuscles.contains(where: avoid.contains) { return false }
                    return true
                }
                .sorted { a, b in
                    let ra = rank(a, preferCompound: true), rb = rank(b, preferCompound: true)
                    if ra != rb { return ra < rb }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
        }

        var seen = Set<String>()
        var result: [Exercise] = []
        var i = 0
        while result.count < limit, perMuscle.contains(where: { !$0.isEmpty }) {
            let m = i % perMuscle.count
            if !perMuscle[m].isEmpty {
                let ex = perMuscle[m].removeFirst()
                if seen.insert(ex.id).inserted { result.append(ex) }
            }
            i += 1
        }
        return result
    }

    private func buildItems(
        for template: DayTemplate,
        priority: [Muscle],
        count: Int,
        allowedEquipment: Set<Equipment>,
        avoidMuscles: Set<Muscle>,
        answers: QuizAnswers
    ) -> [GeneratedItem] {
        // Order this day's target muscles by the user's global priority, then template order.
        let orderedTargets = template.muscles.sorted { lhs, rhs in
            let li = priority.firstIndex(of: lhs) ?? Int.max
            let ri = priority.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            let ti = template.muscles.firstIndex(of: lhs) ?? 0
            let tj = template.muscles.firstIndex(of: rhs) ?? 0
            return ti < tj
        }

        var chosen: [Exercise] = []
        var usedIDs = Set<String>()

        // One pass picking the best exercise per target muscle, looping until we hit `count`.
        var pass = 0
        while chosen.count < count, pass < 4 {
            for muscle in orderedTargets where chosen.count < count {
                let candidate = bestExercise(
                    for: muscle,
                    allowedEquipment: allowedEquipment,
                    avoidMuscles: avoidMuscles,
                    excluding: usedIDs,
                    preferCompound: pass == 0
                )
                if let candidate {
                    chosen.append(candidate)
                    usedIDs.insert(candidate.id)
                }
            }
            pass += 1
        }

        return chosen.map { ex in
            GeneratedItem(exId: ex.id, sets: setTemplate(for: ex, answers: answers))
        }
    }

    /// The best catalog exercise for a muscle under the constraints, or nil.
    private func bestExercise(
        for muscle: Muscle,
        allowedEquipment: Set<Equipment>,
        avoidMuscles: Set<Muscle>,
        excluding usedIDs: Set<String>,
        preferCompound: Bool
    ) -> Exercise? {
        let candidates = catalog.exercises(forMuscle: muscle).filter { ex in
            guard !usedIDs.contains(ex.id) else { return false }
            // Equipment must be permitted; missing equipment counts as bodyweight.
            if !allowedEquipment.contains(ex.equipment ?? .bodyOnly) { return false }
            // Don't load an avoided region as a primary mover.
            if !avoidMuscles.isEmpty, ex.primaryMuscles.contains(where: avoidMuscles.contains) { return false }
            // Must actually target this muscle as primary for a strong stimulus.
            return ex.primaryMuscles.contains(muscle)
        }
        // Deterministic ranking: compound first (if preferred), then strength category,
        // then stable by name.
        return candidates.min { a, b in
            let aScore = rank(a, preferCompound: preferCompound)
            let bScore = rank(b, preferCompound: preferCompound)
            if aScore != bScore { return aScore < bScore }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func rank(_ ex: Exercise, preferCompound: Bool) -> Int {
        var score = 0
        if preferCompound { score += ex.mechanic == .compound ? 0 : 2 }
        score += ex.category == .strength ? 0 : 1
        return score
    }

    // MARK: Set/rep prescription

    private func setTemplate(for ex: Exercise, answers: QuizAnswers) -> [GeneratedSet] {
        let setCount: Int = {
            switch answers.experience {
            case .beginner: return 3
            case .intermediate: return ex.mechanic == .compound ? 4 : 3
            case .advanced: return 4
            }
        }()
        let reps: Int = {
            switch answers.goal {
            case .buildMuscle, .recomp: return 10
            case .loseWeight: return 13
            case .sport: return 8
            }
        }()
        let rpe: Int = {
            switch answers.experience {
            case .beginner: return 7
            case .intermediate: return 8
            case .advanced: return 9
            }
        }()
        let weight = Self.startingWeight(for: ex)
        return Array(repeating: GeneratedSet(weightKg: weight, reps: reps, rpe: rpe), count: setCount)
    }

    /// A sensible starting prescription (kg) the user can tune. Bodyweight = 0.
    static func startingWeight(for ex: Exercise) -> Double {
        switch ex.equipment {
        case .none, .bodyOnly, .bands, .foamRoll, .exerciseBall: return 0
        case .barbell, .ezCurlBar: return ex.mechanic == .compound ? 40 : 20
        case .dumbbell, .kettlebells: return ex.mechanic == .compound ? 16 : 8
        case .machine, .cable: return 25
        case .medicineBall, .other: return 6
        }
    }

    // MARK: Priorities & cosmetics

    private func priorityMuscles(_ answers: QuizAnswers) -> [Muscle] {
        // A known sport biases the plan; "Other"/custom sports have no fixed mapping
        // (empty priorities) and fall through to the general list below.
        if answers.goal == .sport, let sport = answers.sport, !sport.priorityMuscles.isEmpty {
            return sport.priorityMuscles
        }
        // General hypertrophy / recomp / fat-loss: big movers first.
        return [.chest, .lats, .quadriceps, .hamstrings, .shoulders, .glutes,
                .middleBack, .biceps, .triceps, .calves, .abdominals]
    }

    private func exercisesPerWorkout(minutes: Int) -> Int {
        min(6, max(3, minutes / 12))
    }

    private func headline(for goal: Goal) -> String {
        switch goal {
        case .buildMuscle: return "Your Hypertrophy Plan"
        case .loseWeight:  return "Your Fat-Loss Plan"
        case .recomp:      return "Your Recomposition Plan"
        case .sport:       return "Your Sport Plan"
        }
    }

    static func planColor(for goal: Goal) -> String {
        switch goal {
        case .buildMuscle: return "#FF6A3D"
        case .loseWeight:  return "#2FA779"
        case .recomp:      return "#3D7DFF"
        case .sport:       return "#B36AFF"
        }
    }

    /// Weekdays spread across the week for `count` training days.
    static func weekdays(count: Int) -> [Weekday] {
        switch count {
        case ...2: return [.mon, .thu]
        case 3:    return [.mon, .wed, .fri]
        case 4:    return [.mon, .tue, .thu, .fri]
        case 5:    return [.mon, .tue, .wed, .fri, .sat]
        case 6:    return [.mon, .tue, .wed, .thu, .fri, .sat]
        default:   return [.mon, .tue, .wed, .thu, .fri, .sat, .sun] // 7 days, no rest day
        }
    }
}

// MARK: - Splits & day templates

struct DayTemplate: Equatable, Sendable {
    var name: String
    var muscles: [Muscle]
}

struct Split: Equatable, Sendable {
    var planName: String
    var dayTemplates: [DayTemplate]

    static let push = DayTemplate(name: "Push Day", muscles: [.chest, .shoulders, .triceps])
    static let pull = DayTemplate(name: "Pull Day", muscles: [.lats, .middleBack, .biceps, .traps])
    static let legs = DayTemplate(name: "Leg Day", muscles: [.quadriceps, .hamstrings, .glutes, .calves])
    static let upper = DayTemplate(name: "Upper Day", muscles: [.chest, .lats, .shoulders, .biceps, .triceps])
    static let lower = DayTemplate(name: "Lower Day", muscles: [.quadriceps, .hamstrings, .glutes, .calves])
    static let full = DayTemplate(name: "Full Body", muscles: [.chest, .lats, .quadriceps, .shoulders, .hamstrings])
    static let arms = DayTemplate(name: "Arms & Core", muscles: [.biceps, .triceps, .forearms, .abdominals])

    /// Picks a split appropriate to the number of training days.
    static func choose(forDays days: Int) -> Split {
        switch days {
        case ...2:
            return Split(planName: "Upper / Lower", dayTemplates: [upper, lower])
        case 3:
            return Split(planName: "Push · Pull · Legs", dayTemplates: [push, pull, legs])
        case 4:
            return Split(planName: "Upper / Lower", dayTemplates: [upper, lower, upper, lower])
        case 5:
            return Split(planName: "Push · Pull · Legs + Upper / Lower",
                         dayTemplates: [push, pull, legs, upper, lower])
        case 6:
            return Split(planName: "Push · Pull · Legs ×2",
                         dayTemplates: [push, pull, legs, push, pull, legs])
        default:
            // 7 days, no rest day: high-frequency week touching every region.
            return Split(planName: "Push · Pull · Legs + Upper / Lower + Arms",
                         dayTemplates: [push, pull, legs, upper, lower, arms, full])
        }
    }
}
