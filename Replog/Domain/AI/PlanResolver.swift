//
//  PlanResolver.swift
//  Replog
//
//  Turns an AI `PlanBlueprint` into a concrete `GeneratedPlan` of REAL catalog exercises.
//  The model decides programming (split, per-day muscles, volume, rep/RPE); this resolver
//  maps each day's muscle targets onto catalog exercises via the deterministic selector,
//  so every exercise has a valid id and bundled image. Pure & fully unit-testable.
//

import Foundation

struct PlanResolver {
    let generator: PlanGenerator

    init(generator: PlanGenerator = PlanGenerator()) {
        self.generator = generator
    }

    /// Resolves a blueprint into a plan of catalog exercises honoring the user's constraints.
    func resolve(_ blueprint: PlanBlueprint, answers: QuizAnswers) -> GeneratedPlan {
        let dayCount = max(1, blueprint.workouts.count)
        // Normalize to distinct, sensibly spread weekdays regardless of what the model suggested.
        let days = PlanGenerator.weekdays(count: dayCount)

        var workouts: [GeneratedWorkout] = []
        for (i, wb) in blueprint.workouts.enumerated() {
            let muscles = wb.targetMuscles.compactMap { Muscle.lenient($0) }
            let count = clamp(wb.exerciseCount, 3, 6, default: 4)

            // Map this day's muscles to real catalog exercises; fall back to global priority
            // muscles if the AI's targets yielded nothing under the equipment/injury filters.
            var items = generator.selectItems(targetMuscles: muscles, count: count, answers: answers)
            if items.isEmpty {
                items = generator.selectItems(targetMuscles: [], count: count, answers: answers)
            }

            // Apply the model's rep/RPE/set scheme, keeping the selector's starting weights.
            let reps = clamp(wb.reps, 1, 30, default: 10)
            let rpe = clamp(wb.rpe, 5, 10, default: 8)
            let setCount = clamp(wb.sets, 1, 6, default: 3)
            let scheduled = items.map { item -> GeneratedItem in
                let weight = item.sets.first?.weightKg ?? 0
                let sets = Array(repeating: GeneratedSet(weightKg: weight, reps: reps, rpe: rpe),
                                 count: setCount)
                return GeneratedItem(exId: item.exId, sets: sets)
            }

            let day = i < days.count ? days[i] : Weekday.allCases[i % Weekday.allCases.count]
            let name = wb.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(i + 1)" : wb.name
            workouts.append(GeneratedWorkout(name: name, day: day, items: scheduled))
        }

        let planName = blueprint.planName.trimmingCharacters(in: .whitespaces)
        let headline = blueprint.headline.trimmingCharacters(in: .whitespaces)
        return GeneratedPlan(
            name: planName.isEmpty ? "Your Plan" : planName,
            colorHex: PlanGenerator.planColor(for: answers.goal),
            workouts: workouts,
            headline: headline.isEmpty ? "Your Plan" : headline
        )
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int, default def: Int) -> Int {
        guard value >= lo else { return value <= 0 ? def : lo }
        return min(value, hi)
    }
}
