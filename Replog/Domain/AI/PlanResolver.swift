//
//  PlanResolver.swift
//  Replog
//
//  Turns the model's per-day `DaySelection` (picks by candidate number, with reasons) into
//  concrete `GeneratedItem`s of REAL catalog exercises plus per-exercise report notes.
//  Invalid/duplicate picks are dropped and any shortfall is filled from the best unused
//  candidates, so the day is always complete. Pure & fully unit-testable.
//

import Foundation

struct PlanResolver {

    static let defaultReason = "Chosen to add balanced, effective volume for this day's focus."

    nonisolated init() {}

    /// Resolves one day's model selection against its candidate list.
    func resolveDay(day: DayFraming, selection: DaySelection, candidates: [Exercise])
        -> (items: [GeneratedItem], notes: [ExerciseNote]) {
        guard !candidates.isEmpty else { return ([], []) }
        let count = min(clamp(day.exerciseCount, 3, 6, default: 4), candidates.count)
        let reps = clamp(day.reps, 1, 30, default: 10)
        let rpe = clamp(day.rpe, 5, 10, default: 8)
        let setCount = clamp(day.sets, 1, 6, default: 3)

        var chosen: [(ex: Exercise, reason: String)] = []
        var used = Set<Int>()

        // The model's picks, in order, validated against the candidate list.
        for pick in selection.picks where chosen.count < count {
            let idx = pick.number - 1
            guard candidates.indices.contains(idx), !used.contains(idx) else { continue }
            used.insert(idx)
            let reason = pick.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            chosen.append((candidates[idx], reason.isEmpty ? Self.defaultReason : reason))
        }
        // Fill any shortfall from the best unused candidates (deterministic).
        var ci = 0
        while chosen.count < count, ci < candidates.count {
            if !used.contains(ci) { used.insert(ci); chosen.append((candidates[ci], Self.defaultReason)) }
            ci += 1
        }

        let items = chosen.map { entry -> GeneratedItem in
            let weight = PlanGenerator.startingWeight(for: entry.ex)
            let sets = Array(repeating: GeneratedSet(weightKg: weight, reps: reps, rpe: rpe), count: setCount)
            return GeneratedItem(exId: entry.ex.id, sets: sets)
        }
        let notes = chosen.map { ExerciseNote(name: $0.ex.name, reason: $0.reason) }
        return (items, notes)
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int, default def: Int) -> Int {
        guard value >= lo else { return value <= 0 ? def : lo }
        return min(value, hi)
    }
}
