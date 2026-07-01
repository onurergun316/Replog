//
//  AIPlanService.swift
//  Replog
//
//  The Apple Intelligence boundary. Generation is genuinely model-driven and two-stage:
//
//   1. Framing call — the model designs the split (per-day muscle focus, volume, rep/RPE
//      scheme) and writes the report's overall sections.
//   2. Per-day selection calls — for each day the model is given a numbered list of REAL
//      catalog exercises (filtered to the user's equipment/injuries) and picks specific ones,
//      justifying each. Picks are validated against the catalog so refs/images stay valid.
//
//  A non-zero sampling temperature means the same answers can yield different, equally-valid
//  plans across sessions — as the user expects from an AI. If the model is unavailable or
//  errors, it falls back to the deterministic engine (clearly flagged via `usedAppleIntelligence`).
//

import Foundation
import FoundationModels

@MainActor
struct AIPlanService {

    /// A generated plan plus its saved report and which engine produced it.
    struct Result: Equatable, Sendable {
        var plan: GeneratedPlan
        var reportMarkdown: String
        var usedAppleIntelligence: Bool
    }

    let generator: PlanGenerator
    let resolver: PlanResolver
    /// Forces the deterministic path (used by tests so they never invoke the live model).
    let forceFallback: Bool
    /// Sampling temperature — higher means more run-to-run variety.
    let temperature: Double

    nonisolated init(catalog: ExerciseCatalog = .shared, forceFallback: Bool = false, temperature: Double = 1.0) {
        self.generator = PlanGenerator(catalog: catalog)
        self.resolver = PlanResolver()
        self.forceFallback = forceFallback
        self.temperature = temperature
    }

    /// Whether Apple Intelligence can generate on this device right now.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Generates a plan + report. Uses Apple Intelligence when available, else falls back.
    func generate(_ answers: QuizAnswers) async -> Result {
        guard !forceFallback, Self.isAvailable else {
            return Self.fallback(answers: answers, generator: generator)
        }
        do {
            return try await generateWithAI(answers)
        } catch {
            return Self.fallback(answers: answers, generator: generator)
        }
    }

    // MARK: - Live two-stage generation

    private func generateWithAI(_ answers: QuizAnswers) async throws -> Result {
        let options = GenerationOptions(temperature: temperature)

        // 1) Framing: the model designs the split + report sections.
        let framingSession = LanguageModelSession(instructions: Self.framingInstructions)
        let framing = try await framingSession.respond(
            to: Self.framingPrompt(for: answers),
            generating: PlanFraming.self,
            options: options
        ).content

        guard !framing.workouts.isEmpty else {
            return Self.fallback(answers: answers, generator: generator)
        }

        // 2) Per-day: the model selects + justifies specific real exercises.
        let weekdays = PlanGenerator.weekdays(count: framing.workouts.count)
        var workouts: [GeneratedWorkout] = []
        var reportDays: [PerDayNote] = []

        for (index, day) in framing.workouts.enumerated() {
            let muscles = day.targetMuscles.compactMap { Muscle.lenient($0) }
            let candidates = generator.candidates(forMuscles: muscles, answers: answers, limit: 14)
            guard !candidates.isEmpty else { continue }

            let count = max(3, min(6, day.exerciseCount))
            let selectionSession = LanguageModelSession(instructions: Self.selectionInstructions)
            let selection = try await selectionSession.respond(
                to: Self.selectionPrompt(day: day, candidates: candidates, count: count, answers: answers),
                generating: DaySelection.self,
                options: options
            ).content

            let resolved = resolver.resolveDay(day: day, selection: selection, candidates: candidates)
            guard !resolved.items.isEmpty else { continue }

            let weekday = index < weekdays.count ? weekdays[index] : Weekday.allCases[index % 7]
            let name = day.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(index + 1)" : day.name
            workouts.append(GeneratedWorkout(name: name, day: weekday, items: resolved.items))
            reportDays.append(PerDayNote(
                dayName: name,
                text: selection.dayRationale.trimmingCharacters(in: .whitespacesAndNewlines),
                exercises: resolved.notes
            ))
        }

        guard !workouts.isEmpty else {
            return Self.fallback(answers: answers, generator: generator)
        }

        let planName = framing.planName.trimmingCharacters(in: .whitespaces)
        let headline = framing.headline.trimmingCharacters(in: .whitespaces)
        let plan = GeneratedPlan(
            name: planName.isEmpty ? "Your Plan" : planName,
            colorHex: PlanGenerator.planColor(for: answers.goal),
            workouts: workouts,
            headline: headline.isEmpty ? "Your Plan" : headline
        )
        let report = PlanReport(
            philosophy: framing.philosophy,
            whyThisSplit: framing.whyThisSplit,
            perDay: reportDays,
            scienceNotes: framing.scienceNotes,
            safetyNotes: framing.safetyNotes,
            encouragement: framing.encouragement
        )
        return Result(plan: plan, reportMarkdown: ReportComposer.markdown(report: report, plan: plan),
                      usedAppleIntelligence: true)
    }

    // MARK: - Deterministic fallback (no model). Directly unit-tested.

    static func fallback(answers: QuizAnswers, generator: PlanGenerator = PlanGenerator()) -> Result {
        let plan = generator.generate(answers)
        let report = ReportComposer.fallbackMarkdown(answers: answers, plan: plan)
        return Result(plan: plan, reportMarkdown: report, usedAppleIntelligence: false)
    }

    // MARK: - Prompts

    static let framingInstructions = CoachingKnowledge.grounded("""
    You are an elite, caring strength & conditioning coach and exercise scientist who designs \
    safe, evidence-based resistance-training programs tailored to the individual. Use warm, plain, \
    encouraging language. Design the split and explain your reasoning thoroughly, citing the \
    principles below in plain words.
    """)

    static let selectionInstructions = CoachingKnowledge.grounded("""
    You are an elite exercise scientist selecting specific exercises for one training day from a \
    provided list of real, available exercises. Choose the best mix of compound and isolation \
    movements for the day's muscles and the person's level and equipment. For EACH exercise, \
    explain in plain language what it trains and why it earns its place in this session. Only \
    choose from the numbered candidates given.
    """)

    static func framingPrompt(for answers: QuizAnswers) -> String {
        """
        Design a personalized resistance-training plan for this person:

        \(profileLines(answers))

        Produce exactly \(answers.daysPerWeek) training day(s). For each day give a name, its 2-4 \
        primary muscle groups (lowercase single words), the number of exercises (3-6), and the rep, \
        RPE, and set scheme. Then write the report sections: philosophy, why this split and why these \
        muscles are paired together, the science, safety adaptations, and an encouraging note.
        """
    }

    static func selectionPrompt(day: DayFraming, candidates: [Exercise], count: Int, answers: QuizAnswers) -> String {
        let list = candidates.enumerated().map { i, ex in
            let muscle = ex.primaryMuscles.first?.displayName ?? "—"
            let equip = ex.equipment?.displayName ?? "Bodyweight"
            let mech = ex.mechanic?.displayName ?? ""
            return "\(i + 1). \(ex.name) — \(muscle), \(equip)\(mech.isEmpty ? "" : ", \(mech)")"
        }.joined(separator: "\n")

        return """
        Training day: "\(day.name)" focusing on \(day.targetMuscles.joined(separator: ", ")).
        Person: \(answers.goal.displayName), \(answers.experience.displayName), equipment: \
        \(answers.equipmentDescription)\(answers.injuries.isEmpty ? "" : ", limitations: \(answers.injuries.map(\.displayName).joined(separator: ", "))").

        Choose exactly \(count) exercises for this day from the candidates below, in the order they \
        should be performed (compound movements first). Give the candidate number and a clear reason \
        for each.

        Candidates:
        \(list)
        """
    }

    private static func profileLines(_ answers: QuizAnswers) -> String {
        var lines: [String] = []
        if !answers.fullName.isEmpty { lines.append("Name: \(answers.fullName)") }
        lines.append("Goal: \(answers.goal.displayName)")
        if answers.goal == .sport, let sport = answers.sport { lines.append("Sport: \(sport.displayName)") }
        lines.append("Experience: \(answers.experience.displayName)")
        lines.append("Sex: \(answers.sex.displayName)")
        lines.append("Age: \(answers.age)")
        lines.append("Height: \(answers.heightCm) cm")
        lines.append("Body weight: \(Int(answers.bodyWeightKg)) kg")
        if let bmi = answers.bmi {
            lines.append(String(format: "BMI: %.1f (%@)", bmi, answers.bmiCategory ?? ""))
        }
        lines.append("Training days per week: \(answers.daysPerWeek)")
        lines.append("Time per session: ~\(answers.minutesPerSession) min")
        lines.append("Equipment available (use ONLY these): \(answers.equipmentDescription)")
        lines.append("Injuries / limitations: \(answers.injuries.isEmpty ? "none" : answers.injuries.map(\.displayName).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }
}
