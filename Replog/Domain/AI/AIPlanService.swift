//
//  AIPlanService.swift
//  Replog
//
//  The Apple Intelligence boundary. When the on-device model is available it produces a
//  structured `PlanBlueprint` via guided generation; `PlanResolver` maps that onto real
//  catalog exercises and `ReportComposer` renders the saved report. When the model is
//  unavailable (or errors), it falls back to the deterministic engine + a templated report,
//  so the app always produces a valid plan + report. The pure fallback is unit-tested
//  directly; the live model call is a thin, non-deterministic seam verified on-device.
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

    nonisolated init(catalog: ExerciseCatalog = .shared, forceFallback: Bool = false) {
        let generator = PlanGenerator(catalog: catalog)
        self.generator = generator
        self.resolver = PlanResolver(generator: generator)
        self.forceFallback = forceFallback
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
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: Self.prompt(for: answers),
                generating: PlanBlueprint.self
            )
            let blueprint = response.content
            let plan = resolver.resolve(blueprint, answers: answers)
            // Reject a degenerate model result and use the deterministic engine instead.
            guard !plan.workouts.isEmpty, plan.workouts.allSatisfy({ !$0.items.isEmpty }) else {
                return Self.fallback(answers: answers, generator: generator)
            }
            let report = ReportComposer.markdown(
                report: PlanReport(blueprint: blueprint), answers: answers, plan: plan)
            return Result(plan: plan, reportMarkdown: report, usedAppleIntelligence: true)
        } catch {
            return Self.fallback(answers: answers, generator: generator)
        }
    }

    /// Pure deterministic fallback (no model). Directly unit-tested.
    static func fallback(answers: QuizAnswers, generator: PlanGenerator = PlanGenerator()) -> Result {
        let plan = generator.generate(answers)
        let report = ReportComposer.fallbackMarkdown(answers: answers, plan: plan)
        return Result(plan: plan, reportMarkdown: report, usedAppleIntelligence: false)
    }

    // MARK: - Prompt

    static let instructions = """
    You are an elite, caring strength & conditioning coach and exercise scientist. You design \
    safe, evidence-based resistance-training programs tailored to the individual. Ground every \
    decision in established science — progressive overload, ~10–20 weekly sets per muscle, \
    training each muscle about twice weekly, appropriate rep ranges and RPE autoregulation, and \
    adequate recovery. Use warm, plain, encouraging language that shows genuine care for the \
    person's health and well-being. Always return exactly the requested number of training days, \
    each with its primary muscle groups, exercise count, and rep/RPE/set scheme.
    """

    static func prompt(for answers: QuizAnswers) -> String {
        var lines: [String] = []
        if !answers.fullName.isEmpty { lines.append("Name: \(answers.fullName)") }
        lines.append("Goal: \(answers.goal.displayName)")
        if answers.goal == .sport, let sport = answers.sport {
            lines.append("Sport: \(sport.displayName)")
        }
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
        lines.append("Equipment: \(answers.equipment.displayName)")
        let injuries = answers.injuries.isEmpty
            ? "none" : answers.injuries.map(\.displayName).joined(separator: ", ")
        lines.append("Injuries / limitations: \(injuries)")

        return """
        Design a personalized resistance-training plan for this person:

        \(lines.joined(separator: "\n"))

        Produce exactly \(answers.daysPerWeek) training day(s). For each day give a name, its 2–4 \
        primary muscle groups (lowercase single words), how many exercises (3–6), and the rep, \
        RPE, and set scheme. Then write the coach's report sections explaining your reasoning, the \
        science, safety adaptations for any injuries, and an encouraging note.
        """
    }
}
