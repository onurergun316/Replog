//
//  AIPlanServiceTests.swift
//  ReplogTests
//
//  The Apple Intelligence boundary's deterministic surfaces: the prompt builder embeds
//  the user's profile, and the fallback always yields a valid plan + report.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct AIPlanServiceTests {

    @Test func promptEmbedsUserProfile() {
        var a = QuizAnswers()
        a.firstName = "Sam"; a.lastName = "Lee"
        a.goal = .sport; a.sport = .running
        a.heightCm = 178; a.bodyWeightKg = 72
        a.daysPerWeek = 4
        a.injuries = [.knee]
        let prompt = AIPlanService.prompt(for: a)

        #expect(prompt.contains("Sam Lee"))
        #expect(prompt.contains("Running"))
        #expect(prompt.contains("178 cm"))
        #expect(prompt.contains("4"))
        #expect(prompt.contains("Knee"))
        #expect(prompt.contains("exactly 4"))
    }

    @Test func promptHandlesNoNameAndNoInjuries() {
        let prompt = AIPlanService.prompt(for: QuizAnswers())
        #expect(prompt.contains("Injuries / limitations: none"))
        #expect(!AIPlanService.instructions.isEmpty)
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
