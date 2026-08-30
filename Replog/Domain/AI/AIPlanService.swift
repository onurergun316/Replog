//
//  AIPlanService.swift
//  Replog
//
//  The Apple Intelligence boundary — now program-driven. Generation is genuinely model-driven
//  and two-stage, but grounded in the curated program library rather than invented from scratch:
//
//   1. Framing call — the model is handed a numbered shortlist of the best-matching real
//      programs (from `ProgramMatcher`, disclaimer programs excluded) and picks ONE, with a
//      one-sentence justification, then writes the report's overall sections.
//   2. Per-day selection calls — for each day of the chosen program, the model is given, per
//      slot, a numbered list of REAL catalog exercises that fit the slot's movement pattern +
//      the user's equipment, and picks one exercise per slot. Picks are validated against the
//      slot's candidate set so refs/images/patterns stay valid.
//
//  If the model is unavailable or errors, it falls back deterministically: `ProgramMatcher`'s
//  top auto-pickable program is built via the same slot resolver (no model), and if even that
//  yields nothing (e.g. a program with no discrete days) it falls back to the legacy split
//  generator. The engine used is always flagged via `usedAppleIntelligence`.
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
        /// One-sentence rationale for the chosen program (model-written, or a templated line
        /// on the deterministic path). Empty for the legacy split fallback.
        var justification: String = ""
    }

    let generator: PlanGenerator
    let programCatalog: ProgramCatalog
    /// Forces the deterministic path (used by tests so they never invoke the live model).
    let forceFallback: Bool
    /// Sampling temperature — higher means more run-to-run variety.
    let temperature: Double

    /// The most candidate programs ever shown to the framing model, and the floor the budget
    /// trimmer will not go below.
    static let maxCandidates = 5
    static let minCandidates = 3

    nonisolated init(catalog: ExerciseCatalog = .shared,
                     programCatalog: ProgramCatalog = .shared,
                     forceFallback: Bool = false,
                     temperature: Double = 1.0) {
        self.generator = PlanGenerator(catalog: catalog)
        self.programCatalog = programCatalog
        self.forceFallback = forceFallback
        self.temperature = temperature
    }

    /// Whether Apple Intelligence can generate on this device right now.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Generates a plan + report. Uses Apple Intelligence when available, else falls back.
    /// `athlete` carries the user's real logged training (empty on first onboarding); a
    /// non-empty history also lets prerequisite-gated programs qualify.
    func generate(_ answers: QuizAnswers, athlete: AthleteContext = .empty) async -> Result {
        let context = MatchContext.from(answers, satisfiesPrerequisites: !athlete.isEmpty)
        // Auto-pickable candidates only — disclaimer programs are never auto-selected.
        let candidates = ProgramMatcher.rank(context, in: programCatalog)
            .filter { $0.autoPickable }
            // A program that cannot fit the athlete's session — or that would use less than
            // half of it — is not a plan for this athlete. Ranking always yields a winner,
            // so without this the app would recommend a 40-minute program to someone who set
            // aside 90 and call it a match. Better to build to their actual time and days.
            .filter { ProgramMatcher.fitsTheAthlete($0.program, for: context) }
        let shortlist = Array(candidates.prefix(Self.maxCandidates))

        guard !shortlist.isEmpty else {
            // Nothing in the library fits: the split generator sizes each session from the
            // athlete's own minutes and days, which is the honest answer here.
            return Self.legacyFallback(answers: answers, generator: generator)
        }

        guard !forceFallback, Self.isAvailable else {
            return programFallback(program: shortlist[0].program, answers: answers)
        }
        do {
            return try await generateWithAI(answers, athlete: athlete, candidates: shortlist)
        } catch {
            return programFallback(program: shortlist[0].program, answers: answers)
        }
    }

    // MARK: - Live two-stage generation

    private func generateWithAI(_ answers: QuizAnswers,
                                athlete: AthleteContext,
                                candidates: [ProgramMatch]) async throws -> Result {
        let options = GenerationOptions(temperature: temperature)

        // 1) Framing: the model picks one program and writes the report sections.
        let framingSession = LanguageModelSession(instructions: Self.framingInstructions)
        let framing = try await framingSession.respond(
            to: Self.framingPrompt(candidates: candidates, answers: answers, athlete: athlete),
            generating: ProgramFraming.self,
            options: options
        ).content

        let idx = framing.chosenProgramNumber - 1
        let chosen = candidates.indices.contains(idx) ? candidates[idx].program : candidates[0].program
        guard !chosen.days.isEmpty else {
            // Chosen program has no discrete days (e.g. a couch-to-5k plan) — deterministic path.
            return programFallback(program: chosen, answers: answers)
        }

        // 2) Per-day: the model picks one real exercise per slot.
        //
        // The week is the program's templates cycled up to its days per week — a 6-day PPL
        // is three templates run twice — so the model is asked ONCE per template and the
        // answer is reused for its repeats. Asking again would double the calls and could
        // return a different Push day the second time round.
        // Only templates that have candidates for THIS athlete can become sessions: an injury
        // or an equipment gap can empty a whole day, and a dropped day is a day the athlete
        // asked for and did not get. The week is laid out over what survives.
        let usable = chosen.days.filter { !slotCandidateEntries(for: $0, answers: answers).isEmpty }
        guard !usable.isEmpty else { return programFallback(program: chosen, answers: answers) }

        let schedule = ProgramPlanBuilder.schedule(usable, sessions: answers.daysPerWeek)
        let weekdays = PlanGenerator.weekdays(count: max(schedule.count, 1))
        var workouts: [GeneratedWorkout] = []
        var reportDays: [PerDayNote] = []
        var resolutions: [Int: (resolved: ProgramPlanBuilder.DayResolution, rationale: String)] = [:]

        for (index, scheduled) in schedule.enumerated() {
            let day = scheduled.day
            if resolutions[scheduled.templateIndex] == nil {
                let entries = slotCandidateEntries(for: day, answers: answers)
                guard !entries.isEmpty else { continue }

                let selectionSession = LanguageModelSession(instructions: Self.selectionInstructions)
                let selection = try await selectionSession.respond(
                    to: Self.slotSelectionPrompt(day: day, entries: entries, answers: answers),
                    generating: DaySelection.self,
                    options: options
                ).content

                let picks = alignPicks(selection: selection, entries: entries, slotCount: day.slots.count)
                let resolved = ProgramPlanBuilder.resolveDay(day, answers: answers,
                                                             catalog: generator.catalog, picks: picks)
                resolutions[scheduled.templateIndex] = (
                    resolved, selection.dayRationale.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            guard let entry = resolutions[scheduled.templateIndex], !entry.resolved.items.isEmpty else { continue }

            let weekday = index < weekdays.count ? weekdays[index] : Weekday.allCases[index % 7]
            workouts.append(GeneratedWorkout(name: scheduled.name, day: weekday, items: entry.resolved.items))
            // One note per template: the report explains each session, not each repeat.
            if scheduled.occurrence == 1 {
                reportDays.append(PerDayNote(dayName: scheduled.name,
                                             text: entry.rationale,
                                             exercises: entry.resolved.notes))
            }
        }

        // The deterministic builder applies the same rules without a model in the loop, so if
        // the model path came up short of the athlete's week, hand it over rather than ship a
        // plan with days missing.
        guard workouts.count == min(max(answers.daysPerWeek, 1), 7) else {
            return programFallback(program: chosen, answers: answers)
        }

        let headline = framing.headline.trimmingCharacters(in: .whitespaces)
        let plan = GeneratedPlan(
            name: chosen.name,
            colorHex: PlanGenerator.planColor(for: answers.goal),
            workouts: workouts,
            headline: headline.isEmpty ? "Your Plan" : headline,
            programId: chosen.id,
            progression: PlanProgressionMeta(type: chosen.progression.type,
                                             rule: chosen.progression.rule ?? "",
                                             deload: chosen.progression.deload ?? "")
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
                      usedAppleIntelligence: true,
                      justification: framing.justification.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Deterministic fallbacks (no model). Directly unit-tested.

    /// Program-driven fallback: build the chosen program with the deterministic slot resolver.
    /// Falls through to the legacy generator if the program can't be materialised.
    func programFallback(program: WorkoutProgram, answers: QuizAnswers) -> Result {
        let plan = ProgramPlanBuilder.plan(from: program, answers: answers, catalog: generator.catalog)
        guard !plan.workouts.isEmpty else {
            return Self.legacyFallback(answers: answers, generator: generator)
        }
        let report = ProgramPlanBuilder.report(for: program, plan: plan, answers: answers)
        return Result(plan: plan, reportMarkdown: ReportComposer.markdown(report: report, plan: plan),
                      usedAppleIntelligence: false,
                      justification: Self.firstSentence(program.whoIsItFor))
    }

    /// Legacy split generator fallback (no program), for when nothing matches or materialises.
    static func legacyFallback(answers: QuizAnswers, generator: PlanGenerator = PlanGenerator()) -> Result {
        let plan = generator.generate(answers)
        let report = ReportComposer.fallbackMarkdown(answers: answers, plan: plan)
        return Result(plan: plan, reportMarkdown: report, usedAppleIntelligence: false)
    }

    // MARK: - Slot candidate plumbing

    /// A day's flat, globally-numbered candidate list, each tagged with the slot it belongs to.
    struct SlotCandidateEntry: Equatable, Sendable {
        var slotIndex: Int
        var exercise: Exercise
    }

    /// Builds the per-slot candidate entries for a day (a few candidates per resolvable slot),
    /// de-duplicating so the same exercise isn't offered twice.
    func slotCandidateEntries(for day: ProgramDay, answers: QuizAnswers, perSlot: Int = 5) -> [SlotCandidateEntry] {
        var seen = Set<String>()
        var entries: [SlotCandidateEntry] = []
        for (i, slot) in day.slots.enumerated() {
            let cands = ProgramPlanBuilder.candidates(for: slot, answers: answers,
                                                      catalog: generator.catalog, limit: perSlot)
            for ex in cands where seen.insert(ex.id).inserted {
                entries.append(SlotCandidateEntry(slotIndex: i, exercise: ex))
            }
        }
        return entries
    }

    /// Maps the model's flat picks back onto slots: the first valid pick belonging to a slot
    /// wins that slot; slots with no valid pick are left nil (the resolver fills them).
    func alignPicks(selection: DaySelection, entries: [SlotCandidateEntry], slotCount: Int) -> [Exercise?] {
        var picks = [Exercise?](repeating: nil, count: slotCount)
        for pick in selection.picks {
            let i = pick.number - 1
            guard entries.indices.contains(i) else { continue }
            let entry = entries[i]
            if picks.indices.contains(entry.slotIndex), picks[entry.slotIndex] == nil {
                picks[entry.slotIndex] = entry.exercise
            }
        }
        return picks
    }

    // MARK: - Prompts

    static let framingInstructions = CoachingKnowledge.grounded("""
    You are an elite, caring strength & conditioning coach and exercise scientist. You are given \
    a shortlist of real, evidence-based training programs and must choose the single best one for \
    the person, then explain your reasoning thoroughly in warm, plain, encouraging language. \
    Choose ONLY from the numbered programs provided.
    """)

    static let selectionInstructions = CoachingKnowledge.grounded("""
    You are an elite exercise scientist filling a training day's slots. Each slot names a movement \
    pattern and lists real, available exercises that fit it. Pick exactly one exercise per slot — \
    the best fit for the person's level and equipment — and explain in plain language why each \
    earns its place. Only choose from the numbered candidates given.
    """)

    /// The framing prompt. Trims the candidate shortlist (never below `minCandidates`) before
    /// trimming the athlete history, so the whole prompt stays within the model's budget.
    static func framingPrompt(candidates: [ProgramMatch], answers: QuizAnswers,
                              athlete: AthleteContext = .empty) -> String {
        var included = candidates
        var base = framingBase(candidates: included, answers: answers)
        // Trim least-relevant candidates until the fixed part fits with room for a response.
        while included.count > minCandidates,
              PromptBudget.tokenCount(for: framingInstructions) + PromptBudget.tokenCount(for: base) > PromptBudget.promptLimit {
            included.removeLast()
            base = framingBase(candidates: included, answers: answers)
        }
        let remaining = PromptBudget.remainingTokens(afterFixed: framingInstructions, base)
        let history = athlete.promptSection(maxTokens: remaining)
        return history.isEmpty ? base : base + "\n\n" + history
    }

    private static func framingBase(candidates: [ProgramMatch], answers: QuizAnswers) -> String {
        let list = candidates.enumerated().map { i, match in
            let p = match.program
            let who = firstSentence(p.whoIsItFor)
            // Session length is listed because the athlete's is: without it the model was
            // asked to fit a program to a time budget it could not see.
            return "\(i + 1). \(p.name) — \(who) (\(p.daysPerWeek)×/week, ~\(p.sessionMinutes) min/session, \(p.durationWeeks) weeks)"
        }.joined(separator: "\n")

        return """
        Choose the single best training program for this person:

        \(profileLines(answers))

        Programs to choose from (pick exactly one by number):
        \(list)

        The program must fit the days per week and the session length above: do not choose a \
        20-minute maintenance circuit for someone with an hour, or an hour-long program for \
        someone with 20 minutes.

        Give the chosen program's number, a one-sentence justification, a headline, and the report \
        sections: philosophy, why this program works, the science, safety adaptations, and an \
        encouraging note.
        """
    }

    /// One day's slot-selection prompt: slots in order, each with its numbered candidate list.
    static func slotSelectionPrompt(day: ProgramDay, entries: [SlotCandidateEntry],
                                    answers: QuizAnswers) -> String {
        var lines: [String] = []
        for (slotIndex, slot) in day.slots.enumerated() {
            let slotEntries = entries.enumerated().filter { $0.element.slotIndex == slotIndex }
            guard !slotEntries.isEmpty else { continue }
            let variant = slot.variant.map { " (\($0))" } ?? ""
            lines.append("Slot \(slotIndex + 1) — \(slot.pattern.displayName)\(variant), \(slot.sets)×\(slot.reps):")
            for (number, entry) in slotEntries {
                let muscle = entry.exercise.primaryMuscles.first?.displayName ?? "—"
                let equip = entry.exercise.equipment?.displayName ?? "Bodyweight"
                lines.append("  \(number + 1). \(entry.exercise.name) — \(muscle), \(equip)")
            }
        }
        return """
        Training day: "\(day.name)". Person: \(answers.goal.displayName), \
        \(answers.experience.displayName), equipment: \(answers.equipmentDescription)\
        \(answers.injuries.isEmpty ? "" : ", limitations: \(answers.injuries.map(\.displayName).joined(separator: ", "))").

        Pick exactly one exercise for each slot, giving its number and a clear reason.

        \(lines.joined(separator: "\n"))
        """
    }

    private static func profileLines(_ answers: QuizAnswers) -> String {
        var lines: [String] = []
        if !answers.fullName.isEmpty { lines.append("Name: \(answers.fullName)") }
        lines.append("Goal: \(answers.goal.displayName)")
        if answers.goal == .sport, !answers.sportLabel.isEmpty { lines.append("Sport: \(answers.sportLabel)") }
        lines.append("Experience: \(answers.experience.displayName)")
        lines.append("Gender: \(answers.gender.displayName)")
        lines.append("Age: \(answers.age)")
        lines.append("Training days per week: \(answers.daysPerWeek)")
        lines.append("Time per session: ~\(answers.minutesPerSession) min")
        lines.append("Equipment available (use ONLY these): \(answers.equipmentDescription)")
        lines.append("Injuries / limitations: \(answers.injuries.isEmpty ? "none" : answers.injuries.map(\.displayName).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    /// The first sentence of a piece of text (up to the first period), trimmed.
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = trimmed.firstIndex(of: ".") else { return trimmed }
        return String(trimmed[..<dot]).trimmingCharacters(in: .whitespaces)
    }
}
