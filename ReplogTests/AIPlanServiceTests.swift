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
