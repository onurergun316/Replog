//
//  CoachEngineTests.swift
//  ReplogTests
//
//  Fixture-persona tests for the explainable coach: the right insight kinds and priorities
//  fire for each situation, reason strings are grounded in the deterministic engines, and a
//  fresh user is never spammed with a stall alert.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct CoachEngineTests {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// A history series for one lift: one session per week at the given top weights (reps fixed).
    private func series(_ exId: String, weights: [Double], reps: Int = 8) -> [HistoryEntry] {
        weights.enumerated().map { i, w in
            HistoryEntry(exId: exId, date: now.addingTimeInterval(Double(i - weights.count) * 7 * 86_400),
                         topW: w, topR: reps, e1rm: Formulas.e1rmRounded(kg: w, reps: reps),
                         sets: [RecordedSet(w: w, r: reps)])
        }
    }

    private func finished(_ exId: String, name: String, weight: Double, reps: Int = 8,
                          isPR: Bool, sets: Int = 4) -> FinishedLift {
        FinishedLift(exId: exId, name: name, topWeightKg: weight, topReps: reps,
                     e1rm: Formulas.e1rmRounded(kg: weight, reps: reps),
                     isPR: isPR, volumeKg: weight * Double(reps * sets))
    }

    // MARK: - Progressing persona

    @Test func progressingSessionYieldsDebriefAndPRNoStall() {
        let hist = series("Squat", weights: [60, 62.5, 65])
        let outcome = SessionOutcome(
            lifts: [finished("Squat", name: "Squat", weight: 65, isPR: true)],
            totalVolumeKg: 65 * 32, previousTotalVolumeKg: 60 * 32, isFullyComplete: true)
        let ctx = CoachContext(goal: .buildMuscle, now: now, justFinished: outcome,
                               historyByExercise: ["Squat": hist], exerciseNames: ["Squat": "Squat"])

        let insights = CoachEngine.insights(ctx)
        let kinds = Set(insights.map(\.kind))
        #expect(kinds.contains(.sessionDebrief))
        #expect(kinds.contains(.milestone))          // the PR
        #expect(!kinds.contains(.stallAlert))
        // The debrief carries the next-session recommendation reason.
        let debrief = try? #require(insights.first { $0.kind == .sessionDebrief })
        #expect(debrief?.body.contains("Next time on Squat:") == true)
        #expect(debrief?.body.contains("up ") == true)   // volume up vs last time
        // The PR insight is high priority.
        #expect(insights.first { $0.kind == .milestone }?.priority == .high)
    }

    // MARK: - Stalling persona

    @Test func stallingSessionYieldsStallAlertWithDeloadReason() throws {
        let hist = series("Bench", weights: [80, 80, 80, 80])   // four flat sessions → plateau
        let outcome = SessionOutcome(
            lifts: [finished("Bench", name: "Bench Press", weight: 80, isPR: false)],
            totalVolumeKg: 80 * 32, previousTotalVolumeKg: 80 * 32, isFullyComplete: true)
        let ctx = CoachContext(goal: .buildMuscle, now: now, justFinished: outcome,
                               historyByExercise: ["Bench": hist], exerciseNames: ["Bench": "Bench Press"])

        let insights = CoachEngine.insights(ctx)
        let stall = try #require(insights.first { $0.kind == .stallAlert })
        #expect(stall.priority == .high)
        #expect(stall.body.contains("stuck"))
        #expect(stall.body.contains("deload to"))         // computed ~10% deload
        #expect(stall.exId == "Bench")
    }

    @Test func stallAlertPrefersProgramDeloadRuleWhenPresent() throws {
        let hist = series("Bench", weights: [80, 80, 80, 80])
        let outcome = SessionOutcome(
            lifts: [finished("Bench", name: "Bench Press", weight: 80, isPR: false)],
            totalVolumeKg: 80 * 32, previousTotalVolumeKg: 80 * 32, isFullyComplete: true)
        let ctx = CoachContext(goal: .buildMuscle, now: now, justFinished: outcome,
                               historyByExercise: ["Bench": hist], exerciseNames: ["Bench": "Bench Press"],
                               programDeloadRule: "every 4th week, drop to 3×5 at 60%")
        let stall = try #require(CoachEngine.insights(ctx).first { $0.kind == .stallAlert })
        #expect(stall.body.contains("every 4th week, drop to 3×5 at 60%"))
    }

    // MARK: - Streak at risk

    @Test func scheduledUndoneWorkoutWithStreakYieldsHighAdherenceAlert() throws {
        let ctx = CoachContext(now: now, workoutStreak: 5,
                               hasScheduledWorkoutToday: true, completedScheduledToday: false)
        let top = try #require(CoachEngine.topInsight(ctx))
        #expect(top.kind == .adherenceInsight)
        #expect(top.priority == .high)
        #expect(top.body.contains("5-workout streak"))
        #expect(top.body.contains("on the line"))
    }

    @Test func adherenceIsSuppressedOnceTodaysWorkoutIsDone() {
        let ctx = CoachContext(now: now, workoutStreak: 5,
                               hasScheduledWorkoutToday: true, completedScheduledToday: true)
        #expect(!CoachEngine.insights(ctx).contains { $0.kind == .adherenceInsight })
    }

    // MARK: - Bodyweight & check-in

    @Test func favorableBodyweightTrendReadsAsRightDirection() throws {
        let bw = BodyweightSnapshot(currentKg: 78, date: now, deltaKg: -0.4,
                                    weeklyRateKg: -0.4, direction: .down, sparklineValues: [])
        let ctx = CoachContext(goal: .loseWeight, now: now, bodyweight: bw)
        let insight = try #require(CoachEngine.insights(ctx).first { $0.kind == .bodyweightTrend })
        #expect(insight.body.contains("down"))
        #expect(insight.body.contains("right direction"))
    }

    @Test func checkInDueYieldsAPrompt() {
        let ctx = CoachContext(now: now, bodyweightCheckInDue: true)
        #expect(CoachEngine.insights(ctx).contains { $0.kind == .checkInPrompt })
    }

    @Test func stallOutranksBodyweightTrendForTheTodayCard() throws {
        let hist = series("Bench", weights: [80, 80, 80, 80])
        let bw = BodyweightSnapshot(currentKg: 78, date: now, deltaKg: -0.4,
                                    weeklyRateKg: -0.4, direction: .down, sparklineValues: [])
        // No finished session → both stall (from history) and bodyweight trend are eligible.
        let ctx = CoachContext(goal: .loseWeight, now: now,
                               historyByExercise: ["Bench": hist], exerciseNames: ["Bench": "Bench Press"],
                               bodyweight: bw)
        let top = try #require(CoachEngine.topInsight(ctx))
        #expect(top.kind == .stallAlert)   // high beats low
    }

    // MARK: - Fresh user / no spam

    @Test func freshUserGetsOnlyWelcome() {
        let ctx = CoachContext(now: now, isFreshUser: true)
        let insights = CoachEngine.insights(ctx)
        #expect(insights.map(\.kind) == [.welcome])
    }

    @Test func freshUserWithOneSessionGetsDebriefNeverStall() {
        let hist = series("Squat", weights: [60])   // a single session
        let outcome = SessionOutcome(
            lifts: [finished("Squat", name: "Squat", weight: 60, isPR: true)],
            totalVolumeKg: 60 * 32, previousTotalVolumeKg: nil, isFullyComplete: true)
        let ctx = CoachContext(goal: .buildMuscle, now: now, justFinished: outcome,
                               historyByExercise: ["Squat": hist], exerciseNames: ["Squat": "Squat"],
                               isFreshUser: true)
        let insights = CoachEngine.insights(ctx)
        #expect(insights.contains { $0.kind == .sessionDebrief })
        #expect(!insights.contains { $0.kind == .stallAlert })     // 1 session can't stall
        #expect(!insights.contains { $0.kind == .welcome })        // debrief supersedes welcome
    }

    @Test func streakMilestoneFiresOnRoundNumbers() {
        let ctx = CoachContext(now: now, workoutStreak: 7)
        #expect(CoachEngine.insights(ctx).contains { $0.kind == .milestone && $0.title.contains("7") })
        let ctx8 = CoachContext(now: now, workoutStreak: 8)   // not a milestone number
        #expect(!CoachEngine.insights(ctx8).contains { $0.kind == .milestone })
    }
}
