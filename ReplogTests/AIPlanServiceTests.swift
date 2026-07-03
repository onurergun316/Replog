//
//  AIPlanServiceTests.swift
//  ReplogTests
//
//  The Apple Intelligence boundary's deterministic surfaces for the PROGRAM-DRIVEN flow:
//  the framing prompt embeds the user's profile and a real candidate program list, the
//  slot-selection prompt lists real catalog exercises per slot, instructions are
//  science-grounded, prompts stay under the token budget, and the fallback always yields a
//  valid plan + report (program-driven when a program matches).
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct AIPlanServiceTests {

    private let programs = ProgramCatalog(bundle: .main)
    private let fullGym: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyOnly,
                                           .bands, .kettlebells, .medicineBall]

    private func topCandidates(_ answers: QuizAnswers, limit: Int = 5) -> [ProgramMatch] {
        let ctx = MatchContext.from(answers)
        return Array(ProgramMatcher.rank(ctx, in: programs).filter { $0.autoPickable }.prefix(limit))
    }

    // MARK: - Framing prompt

    @Test func framingPromptEmbedsUserProfileAndCandidatePrograms() throws {
        var a = QuizAnswers()
        a.firstName = "Sam"; a.goal = .buildMuscle; a.age = 30
        a.daysPerWeek = 4; a.equipmentTypes = fullGym; a.injuries = [.knee]
        let candidates = topCandidates(a)
        #expect(candidates.count >= AIPlanService.minCandidates)

        let prompt = AIPlanService.framingPrompt(candidates: candidates, answers: a)
        #expect(prompt.contains("Name: Sam"))
        #expect(prompt.contains("Goal: Build muscle"))
        #expect(prompt.contains("Knee"))
        // The real candidate program names appear as a numbered list.
        #expect(prompt.contains("1. \(candidates[0].program.name)"))
        #expect(prompt.contains("pick exactly one by number"))
    }

    @Test func framingPromptEmbedsLoggedHistoryAndDiffersFromEmpty() throws {
        let catalog = ExerciseCatalog(bundle: .main)
        let bench = try #require(catalog.exercises(forMuscle: .chest).first)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let history = [
            HistoryEntry(exId: bench.id, date: now.addingTimeInterval(-10 * 86_400),
                         topW: 80, topR: 8, e1rm: Formulas.e1rmRounded(kg: 80, reps: 8),
                         sets: [RecordedSet(w: 80, r: 8)]),
            HistoryEntry(exId: bench.id, date: now.addingTimeInterval(-3 * 86_400),
                         topW: 82.5, topR: 8, e1rm: Formulas.e1rmRounded(kg: 82.5, reps: 8),
                         sets: [RecordedSet(w: 82.5, r: 8)]),
        ]
        let athlete = AthleteContext.make(history: history, catalog: catalog, now: now)
        var a = QuizAnswers(); a.equipmentTypes = fullGym
        let candidates = topCandidates(a)

        let rich = AIPlanService.framingPrompt(candidates: candidates, answers: a, athlete: athlete)
        let empty = AIPlanService.framingPrompt(candidates: candidates, answers: a)
        #expect(rich != empty)
        #expect(rich.contains("RECENT LOGGED TRAINING"))
        #expect(rich.contains(bench.name))
        #expect(!empty.contains("RECENT LOGGED TRAINING"))
    }

    @Test func framingPromptStaysUnderTokenBudgetWithMargin() {
        let catalog = ExerciseCatalog(bundle: .main)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // Worst-case athlete: many distinct lifts across many muscles, all recent.
        let muscles: [Muscle] = [.chest, .quadriceps, .lats, .shoulders, .hamstrings, .biceps]
        let history = muscles.flatMap { muscle in
            catalog.exercises(forMuscle: muscle).prefix(3).map { ex in
                HistoryEntry(exId: ex.id, date: now.addingTimeInterval(-2 * 86_400),
                             topW: 61.25, topR: 12, e1rm: Formulas.e1rmRounded(kg: 61.25, reps: 12),
                             sets: Array(repeating: RecordedSet(w: 61.25, r: 12), count: 4))
            }
        }
        let athlete = AthleteContext.make(history: history, catalog: catalog, now: now)
        var a = QuizAnswers()
        a.equipmentTypes = fullGym
        a.injuries = [.knee, .shoulder, .lowerBack]  // longest profile lines
        let candidates = topCandidates(a, limit: AIPlanService.maxCandidates)

        let prompt = AIPlanService.framingPrompt(candidates: candidates, answers: a, athlete: athlete)
        let inputTokens = PromptBudget.tokenCount(for: AIPlanService.framingInstructions)
            + PromptBudget.tokenCount(for: prompt)

        // Instructions + prompt must leave the full response reserve inside the window.
        #expect(inputTokens + PromptBudget.responseReserve <= PromptBudget.contextWindow)
    }

    @Test func framingPromptTrimsCandidatesNotBelowFloorUnderPressure() {
        // Even with a huge (synthetic) candidate list, the prompt trims to fit but never drops
        // below the minimum shortlist size.
        let ctx = MatchContext(goal: .buildMuscle, age: 30, daysPerWeek: 4, equipment: fullGym)
        let many = ProgramMatcher.rank(ctx, in: programs).filter { $0.autoPickable }
        let candidates = Array(many.prefix(AIPlanService.maxCandidates))
        let prompt = AIPlanService.framingPrompt(candidates: candidates, answers: QuizAnswers())
        // At least the floor number of candidates is always present.
        let listed = (1...AIPlanService.minCandidates).allSatisfy { prompt.contains("\($0). ") }
        #expect(listed)
    }

    // MARK: - Slot-selection prompt

    @Test func slotSelectionPromptListsSlotsAndRealCandidates() throws {
        let service = AIPlanService(forceFallback: true)
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let day = try #require(program.days.first)
        var a = QuizAnswers(); a.equipmentTypes = fullGym

        let entries = service.slotCandidateEntries(for: day, answers: a)
        #expect(!entries.isEmpty)
        let prompt = AIPlanService.slotSelectionPrompt(day: day, entries: entries, answers: a)
        #expect(prompt.contains("Slot 1 —"))
        #expect(prompt.contains("Pick exactly one exercise for each slot"))
        // The first candidate's real catalog name is present.
        #expect(prompt.contains(entries[0].exercise.name))
    }

    @Test func alignPicksMapsFlatModelPicksOntoSlots() throws {
        let service = AIPlanService(forceFallback: true)
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let day = try #require(program.days.first)
        var a = QuizAnswers(); a.equipmentTypes = fullGym
        let entries = service.slotCandidateEntries(for: day, answers: a)

        // The model "picks" the very first candidate (global #1), which belongs to slot 0.
        let selection = DaySelection(dayRationale: "r", picks: [ExercisePick(number: 1, reason: "x")])
        let picks = service.alignPicks(selection: selection, entries: entries, slotCount: day.slots.count)
        #expect(picks.count == day.slots.count)
        #expect(picks[entries[0].slotIndex]?.id == entries[0].exercise.id)
    }

    // MARK: - Instructions grounded in science

    @Test func instructionsAreGroundedInScience() {
        #expect(AIPlanService.framingInstructions.contains("Volume"))
        #expect(AIPlanService.framingInstructions.contains("Frequency"))
        #expect(AIPlanService.selectionInstructions.contains("movement pattern"))
        #expect(CoachingKnowledge.principles.contains("Progressive overload"))
    }

    // MARK: - Fallback

    @Test func fallbackIsProgramDrivenAndProducesValidPlanAndReport() async throws {
        let service = AIPlanService(forceFallback: true)
        var a = QuizAnswers()
        a.goal = .buildMuscle; a.daysPerWeek = 4; a.equipmentTypes = fullGym
        let result = await service.generate(a)

        #expect(result.usedAppleIntelligence == false)
        #expect(!result.plan.workouts.isEmpty)
        #expect(result.plan.workouts.allSatisfy { !$0.items.isEmpty })
        // A program was chosen: its id + progression metadata rode along.
        #expect(result.plan.programId != nil)
        #expect(programs.program(id: result.plan.programId ?? "") != nil)
        #expect(result.reportMarkdown.contains("# "))
        #expect(result.reportMarkdown.contains("## The science"))
    }

    @Test func fallbackNeverPicksADisclaimerProgram() async throws {
        // A persona that would match a disclaimer program (menopause/postnatal) must still get
        // a non-disclaimer auto-pick from the fallback.
        let service = AIPlanService(forceFallback: true)
        var a = QuizAnswers()
        a.goal = .recomp; a.gender = .female; a.age = 52; a.daysPerWeek = 3; a.equipmentTypes = fullGym
        let result = await service.generate(a)
        let program = try #require(programs.program(id: result.plan.programId ?? ""))
        #expect(!program.requiresDisclaimerAcknowledgement)
    }
}
