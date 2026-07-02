//
//  AIPlanServiceTests.swift
//  ReplogTests
//
//  The Apple Intelligence boundary's deterministic surfaces: prompts embed the user's
//  profile and the real candidate list, instructions are science-grounded, and the fallback
//  always yields a valid plan + report.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct AIPlanServiceTests {

    @Test func framingPromptEmbedsUserProfile() {
        var a = QuizAnswers()
        a.firstName = "Sam"
        a.goal = .sport; a.sport = .running
        a.heightCm = 178; a.bodyWeightKg = 72
        a.daysPerWeek = 4
        a.injuries = [.knee]
        let prompt = AIPlanService.framingPrompt(for: a)

        #expect(prompt.contains("Name: Sam"))
        #expect(prompt.contains("Running"))
        #expect(prompt.contains("178 cm"))
        #expect(prompt.contains("exactly 4"))
        #expect(prompt.contains("Knee"))
    }

    @Test func selectionPromptListsNumberedCandidates() {
        let g = PlanGenerator(catalog: ExerciseCatalog(bundle: .main))
        let candidates = g.candidates(forMuscles: [.chest], answers: QuizAnswers(), limit: 6)
        #expect(candidates.count >= 3)
        let day = DayFraming(name: "Push", targetMuscles: ["chest"], exerciseCount: 4, reps: 10, rpe: 8, sets: 4)
        let prompt = AIPlanService.selectionPrompt(day: day, candidates: candidates, count: 4, answers: QuizAnswers())

        #expect(prompt.contains("1. "))
        #expect(prompt.contains("Choose exactly 4"))
        #expect(prompt.contains(candidates[0].name))
    }

    @Test func instructionsAreGroundedInScience() {
        #expect(AIPlanService.framingInstructions.contains("Volume"))
        #expect(AIPlanService.framingInstructions.contains("Frequency"))
        #expect(AIPlanService.selectionInstructions.contains("compound"))
        #expect(CoachingKnowledge.principles.contains("Progressive overload"))
    }

    @Test func framingPromptEmbedsLoggedHistory() throws {
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
        let answers = QuizAnswers()

        let rich = AIPlanService.framingPrompt(for: answers, athlete: athlete)
        let empty = AIPlanService.framingPrompt(for: answers)

        // A persona with history produces a visibly different prompt than an empty one.
        #expect(rich != empty)
        #expect(rich.contains("RECENT LOGGED TRAINING"))
        #expect(rich.contains(bench.name))
        #expect(!empty.contains("RECENT LOGGED TRAINING"))
    }

    @Test func framingPromptStaysUnderTokenBudgetWithMargin() {
        let catalog = ExerciseCatalog(bundle: .main)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // A worst-case athlete: many distinct lifts across many muscles, all recent.
        let muscles: [Muscle] = [.chest, .quadriceps, .lats, .shoulders, .hamstrings, .biceps]
        let history = muscles.flatMap { muscle in
            catalog.exercises(forMuscle: muscle).prefix(3).map { ex in
                HistoryEntry(exId: ex.id, date: now.addingTimeInterval(-2 * 86_400),
                             topW: 61.25, topR: 12, e1rm: Formulas.e1rmRounded(kg: 61.25, reps: 12),
                             sets: Array(repeating: RecordedSet(w: 61.25, r: 12), count: 4))
            }
        }
        let athlete = AthleteContext.make(history: history, catalog: catalog, now: now)
        var answers = QuizAnswers()
        answers.injuries = [.knee, .shoulder, .lowerBack]  // longest profile lines

        let prompt = AIPlanService.framingPrompt(for: answers, athlete: athlete)
        let inputTokens = PromptBudget.estimatedTokens(AIPlanService.framingInstructions)
            + PromptBudget.estimatedTokens(prompt)

        // Instructions + prompt must leave the full response reserve inside the window.
        #expect(inputTokens + PromptBudget.responseReserve <= PromptBudget.contextWindow)
    }

    @Test func selectionPromptAnnotatesLoggedCandidates() throws {
        let catalog = ExerciseCatalog(bundle: .main)
        let g = PlanGenerator(catalog: catalog)
        let candidates = g.candidates(forMuscles: [.chest], answers: QuizAnswers(), limit: 6)
        let logged = try #require(candidates.first)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let history = [HistoryEntry(exId: logged.id, date: now.addingTimeInterval(-86_400),
                                    topW: 80, topR: 8, e1rm: Formulas.e1rmRounded(kg: 80, reps: 8),
                                    sets: [RecordedSet(w: 80, r: 8)])]
        let athlete = AthleteContext.make(history: history, catalog: catalog, now: now)
        let day = DayFraming(name: "Push", targetMuscles: ["chest"], exerciseCount: 4, reps: 10, rpe: 8, sets: 4)

        let prompt = AIPlanService.selectionPrompt(day: day, candidates: candidates, count: 4,
                                                   answers: QuizAnswers(), athlete: athlete)

        #expect(prompt.contains("[logged: last 80 kg × 8"))
        #expect(prompt.contains("prefer keeping ones"))
    }

    @Test func fallbackAlwaysProducesValidPlanAndReport() async {
        let service = AIPlanService(catalog: ExerciseCatalog(bundle: .main), forceFallback: true)
        var a = QuizAnswers()
        a.daysPerWeek = 6
        let result = await service.generate(a)

        #expect(result.usedAppleIntelligence == false)
        #expect(result.plan.workouts.count == 6)
        #expect(result.plan.workouts.allSatisfy { !$0.items.isEmpty })
        #expect(result.reportMarkdown.contains("# "))
        #expect(result.reportMarkdown.contains("## The science"))
    }
}
