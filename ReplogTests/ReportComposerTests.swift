//
//  ReportComposerTests.swift
//  ReplogTests
//
//  The fallback coach report must always exist, be personalized to the quiz answers,
//  and render to well-formed markdown. Also covers the AIPlanService deterministic path.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ReportComposerTests {

    private func samplePlan(_ answers: QuizAnswers) -> GeneratedPlan {
        PlanGenerator(catalog: ExerciseCatalog(bundle: .main)).generate(answers)
    }

    @Test func fallbackReportReflectsGoalDaysAndExperience() {
        var answers = QuizAnswers()
        answers.firstName = "Sam"
        answers.goal = .loseWeight
        answers.daysPerWeek = 4
        answers.experience = .intermediate
        let plan = samplePlan(answers)
        let report = ReportComposer.fallbackReport(answers: answers, plan: plan)

        #expect(report.philosophy.contains("Sam"))
        #expect(report.philosophy.lowercased().contains("lose weight"))
        #expect(report.philosophy.contains("4"))
        #expect(report.perDay.count == plan.workouts.count)
    }

    @Test func fallbackReportNamesInjuriesInSafetySection() {
        var answers = QuizAnswers()
        answers.injuries = [.knee, .shoulder]
        let report = ReportComposer.fallbackReport(answers: answers, plan: samplePlan(answers))
        #expect(report.safetyNotes.contains("Knee"))
        #expect(report.safetyNotes.contains("Shoulder"))
    }

    @Test func fallbackReportGivesGeneralSafetyWhenNoInjuries() {
        let answers = QuizAnswers()
        let report = ReportComposer.fallbackReport(answers: answers, plan: samplePlan(answers))
        #expect(!report.safetyNotes.isEmpty)
        #expect(!report.encouragement.isEmpty)
    }

    @Test func markdownContainsAllSectionsAndHeadline() {
        let answers = QuizAnswers()
        let plan = samplePlan(answers)
        let md = ReportComposer.fallbackMarkdown(answers: answers, plan: plan)
        #expect(md.contains("# \(plan.headline)"))
        #expect(md.contains("## Why this split"))
        #expect(md.contains("## Your training week"))
        #expect(md.contains("## The science"))
        #expect(md.contains("## Staying safe"))
        // One bullet per workout day.
        let bullets = md.components(separatedBy: "\n- ").count - 1
        #expect(bullets == plan.workouts.count)
    }

    @Test func aiPlanServiceFallbackProducesPlanAndReport() {
        var answers = QuizAnswers()
        answers.daysPerWeek = 5
        let result = AIPlanService.fallback(answers: answers)
        #expect(result.usedAppleIntelligence == false)
        #expect(result.plan.workouts.count == 5)
        #expect(!result.reportMarkdown.isEmpty)
        #expect(result.reportMarkdown.contains("# "))
    }
}
