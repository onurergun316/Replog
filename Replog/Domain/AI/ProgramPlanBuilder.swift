//
//  ProgramPlanBuilder.swift
//  Replog
//
//  Turns a chosen library `WorkoutProgram` into a concrete `GeneratedPlan` + `PlanReport` by
//  resolving each `ProgramSlot` to a real catalog exercise (via `PatternMapping`) and its
//  set/rep/rest scheme (via `RepScheme`). This is the shared spine of program-driven planning:
//
//   • The deterministic fallback calls it with no model picks — each slot takes its top
//     candidate — so a program-driven plan exists even without Apple Intelligence.
//   • The live AI path calls `resolveDay` with the model's per-slot picks; each pick is
//     VALIDATED against that slot's candidate set (right pattern family + equipment) and any
//     invalid/missing pick falls back to the slot's top candidate.
//
//  Pure & unit-tested. Slots that resolve to nothing (e.g. a swim slot with no catalog match,
//  or a strength slot the athlete lacks equipment for) are skipped; a day with no resolvable
//  slots is dropped, and a program with no discrete days yields an empty plan (the caller then
//  falls back to the legacy split generator).
//

import Foundation

enum ProgramPlanBuilder {

    /// One day's resolution: concrete items plus the report notes explaining each pick.
    struct DayResolution: Equatable, Sendable {
        var items: [GeneratedItem]
        var notes: [ExerciseNote]
    }

    // MARK: - Deterministic plan (fallback path)

    /// Builds a full plan from a program with no model input (top candidate per slot).
    static func plan(from program: WorkoutProgram, answers: QuizAnswers, catalog: ExerciseCatalog) -> GeneratedPlan {
        let weekdays = PlanGenerator.weekdays(count: max(program.days.count, 1))
        var workouts: [GeneratedWorkout] = []
        for (index, day) in program.days.enumerated() {
            let resolved = resolveDay(day, answers: answers, catalog: catalog)
            guard !resolved.items.isEmpty else { continue }
            let weekday = index < weekdays.count ? weekdays[index] : Weekday.allCases[index % 7]
            let name = day.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(index + 1)" : day.name
            workouts.append(GeneratedWorkout(name: name, day: weekday, items: resolved.items))
        }
        return GeneratedPlan(
            name: program.name,
            colorHex: PlanGenerator.planColor(for: answers.goal),
            workouts: workouts,
            headline: headline(for: program, goal: answers.goal),
            programId: program.id,
            progression: PlanProgressionMeta(type: program.progression.type,
                                             rule: program.progression.rule ?? "",
                                             deload: program.progression.deload ?? "")
        )
    }

    // MARK: - Per-day resolution (shared by fallback + AI)

    /// Resolves one program day. `picks[i]` is an optional pre-chosen exercise for slot `i`
    /// (from the model); it is used only if it validly belongs to that slot's candidate set,
    /// otherwise the slot's top unused candidate is used. Empty `picks` = fully deterministic.
    static func resolveDay(_ day: ProgramDay,
                           answers: QuizAnswers,
                           catalog: ExerciseCatalog,
                           picks: [Exercise?] = []) -> DayResolution {
        var items: [GeneratedItem] = []
        var notes: [ExerciseNote] = []
        var usedIDs = Set<String>()

        for (i, slot) in day.slots.enumerated() {
            let candidates = candidates(for: slot, answers: answers, catalog: catalog)
                .filter { !usedIDs.contains($0.id) }
            guard !candidates.isEmpty else { continue }   // unresolvable slot (e.g. swim) → skip

            // A validated model pick, else the slot's top candidate.
            let modelPick = i < picks.count ? picks[i] : nil
            let chosen = validated(modelPick, against: candidates) ?? candidates[0]
            usedIDs.insert(chosen.id)

            let weight = PlanGenerator.startingWeight(for: chosen)
            let sets = RepScheme.sets(for: slot, startingWeightKg: weight, defaultRPE: defaultRPE(answers))
            items.append(GeneratedItem(exId: chosen.id, sets: sets, restSeconds: slot.restSeconds))
            notes.append(ExerciseNote(name: chosen.name, reason: slotReason(slot: slot, exercise: chosen)))
        }
        return DayResolution(items: items, notes: notes)
    }

    /// The catalog candidates for a single slot, honoring equipment & injuries.
    static func candidates(for slot: ProgramSlot,
                           answers: QuizAnswers,
                           catalog: ExerciseCatalog,
                           limit: Int = 12) -> [Exercise] {
        PatternMapping.candidates(for: slot.pattern,
                                  slotMuscles: slot.primaryMuscles,
                                  allowedEquipment: answers.allowedEquipment,
                                  avoidMuscles: answers.avoidedMuscles,
                                  in: catalog,
                                  limit: limit)
    }

    // MARK: - Report

    /// A program-grounded report explaining the plan and every exercise choice.
    static func report(for program: WorkoutProgram, plan: GeneratedPlan, answers: QuizAnswers) -> PlanReport {
        let name = answers.firstName.trimmingCharacters(in: .whitespaces)
        let greeting = name.isEmpty ? "" : "\(name), "

        let philosophy = "\(greeting.capitalizedFirstChar)your coach chose \(program.name) for you. " +
            "\(program.whoIsItFor)"

        let whyThisSplit = program.scienceRationale.isEmpty
            ? "This program groups its sessions to train each quality with enough frequency to progress while recovering between sessions."
            : program.scienceRationale

        // Per-day notes come from the resolved plan (names + slot reasons already computed).
        let perDay: [PerDayNote] = plan.workouts.map { workout in
            let notes = workout.items.map { item -> ExerciseNote in
                ExerciseNote(name: ReportComposer.prettyName(item.exId), reason: itemReason(item))
            }
            return PerDayNote(dayName: workout.name,
                              text: "Each movement below is chosen to fill a specific role in this session.",
                              exercises: notes)
        }

        var science = ""
        if !program.progression.type.isEmpty && program.progression.type != "none" {
            science += "Progression: \(progressionSentence(program.progression)) "
        }
        if !program.evidence.isEmpty {
            science += "This approach draws on: \(program.evidence.joined(separator: "; "))."
        }
        if science.isEmpty {
            science = "Progress by adding a little load or a rep whenever a set beats its target — small, steady overload compounds."
        }

        var safety = program.cautions.isEmpty
            ? "Warm up before heavy work, keep a rep or two in reserve early, and prioritise sleep — that's when adaptation happens."
            : program.cautions
        if !answers.injuries.isEmpty {
            let list = answers.injuries.map(\.displayName).joined(separator: ", ")
            safety += " We also avoided loading these areas as primary movers: \(list)."
        }

        let encouragement = program.expectedResults.isEmpty
            ? "\(greeting.capitalizedFirstChar)show up, log your sets, and let the progress compound. We've got you."
            : "\(greeting.capitalizedFirstChar)here's what to expect if you stay consistent: \(program.expectedResults)"

        return PlanReport(philosophy: philosophy,
                          whyThisSplit: whyThisSplit,
                          perDay: perDay,
                          scienceNotes: science,
                          safetyNotes: safety,
                          encouragement: encouragement)
    }

    // MARK: - Helpers

    private static func validated(_ pick: Exercise?, against candidates: [Exercise]) -> Exercise? {
        guard let pick else { return nil }
        return candidates.contains(where: { $0.id == pick.id }) ? pick : nil
    }

    private static func defaultRPE(_ answers: QuizAnswers) -> Int {
        switch answers.experience {
        case .beginner: return 7
        case .intermediate: return 8
        case .advanced: return 9
        }
    }

    private static func slotReason(slot: ProgramSlot, exercise: Exercise) -> String {
        let muscles = exercise.primaryMuscles.prefix(2).map(\.displayName).joined(separator: " & ")
        let role = slot.pattern.displayName.lowercased()
        let variant = slot.variant.map { " (\($0))" } ?? ""
        if muscles.isEmpty {
            return "Fills this session's \(role) work\(variant)."
        }
        return "Your \(role) movement\(variant) — trains \(muscles)."
    }

    private static func itemReason(_ item: GeneratedItem) -> String {
        "Programmed for \(item.sets.count)×\(item.sets.first?.reps ?? 0) to drive this session's target adaptation."
    }

    private static func progressionSentence(_ p: ProgramProgression) -> String {
        var parts: [String] = [p.type.replacingOccurrences(of: "_", with: " ")]
        if let rule = p.rule, !rule.isEmpty { parts.append(rule) }
        if let deload = p.deload, !deload.isEmpty { parts.append("Deload: \(deload)") }
        return parts.joined(separator: " — ")
    }

    private static func headline(for program: WorkoutProgram, goal: Goal) -> String {
        switch goal {
        case .buildMuscle: return "Your Muscle-Building Plan"
        case .loseWeight:  return "Your Fat-Loss Plan"
        case .recomp:      return "Your Recomposition Plan"
        case .sport:       return "Your Performance Plan"
        }
    }
}

private extension String {
    /// Capitalizes only the first character ("alex, we…" → "Alex, we…").
    var capitalizedFirstChar: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
