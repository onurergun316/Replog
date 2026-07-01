//
//  ReportComposerTests.swift
//  ReplogTests
//
//  The report renderer + fallback: personalized to the answers, with a per-day and
//  per-exercise breakdown, rendered to well-formed markdown.
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

    @Test func fallbackReportHasPerExerciseNotesForEveryExercise() {
        let answers = QuizAnswers()
        let plan = samplePlan(answers)
        let report = ReportComposer.fallbackReport(answers: answers, plan: plan)
        for (i, day) in report.perDay.enumerated() {
            #expect(day.exercises.count == plan.workouts[i].items.count)
            #expect(day.exercises.allSatisfy { !$0.name.isEmpty && !$0.reason.isEmpty })
        }
    }

    @Test func fallbackReportNamesInjuriesInSafetySection() {
        var answers = QuizAnswers()
        answers.injuries = [.knee, .shoulder]
        let report = ReportComposer.fallbackReport(answers: answers, plan: samplePlan(answers))
        #expect(report.safetyNotes.contains("Knee"))
        #expect(report.safetyNotes.contains("Shoulder"))
    }

    @Test func markdownContainsAllSectionsPerDayAndPerExercise() {
        let answers = QuizAnswers()
        let plan = samplePlan(answers)
        let md = ReportComposer.fallbackMarkdown(answers: answers, plan: plan)
        #expect(md.contains("# \(plan.headline)"))
        #expect(md.contains("## Why this split"))
        #expect(md.contains("## Your training week"))
        #expect(md.contains("### \(plan.workouts[0].name)"))            // per-day heading
        #expect(md.contains("## The science"))
        #expect(md.contains("## Staying safe"))
        let firstExercise = ReportComposer.prettyName(plan.workouts[0].items[0].exId)
        #expect(md.contains("**\(firstExercise)**"))                    // per-exercise bullet
    }

    @Test func prettyNameHumanizesCatalogId() {
        #expect(ReportComposer.prettyName("Alternating_Floor_Press") == "Alternating Floor Press")
    }
}
