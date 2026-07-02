//
//  AthleteContextTests.swift
//  ReplogTests
//
//  The athlete digest that grounds the AI planner in real logged training: per-lift
//  summaries, weekly volume, relevance ordering, windowing, and token-budgeted rendering.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct AthleteContextTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// A real catalog exercise with `muscle` as a PRIMARY mover, so exIds resolve and
    /// weekly volume attributes to the expected muscle.
    private func exercise(_ muscle: Muscle, offset: Int = 0) -> Exercise {
        catalog.exercises(forMuscle: muscle).filter { $0.primaryMuscles.contains(muscle) }[offset]
    }

    private func entry(_ exId: String, daysAgo: Int, topW: Double, topR: Int, sets: Int = 3) -> HistoryEntry {
        HistoryEntry(exId: exId,
                     date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                     topW: topW, topR: topR,
                     e1rm: Formulas.e1rmRounded(kg: topW, reps: topR),
                     sets: Array(repeating: RecordedSet(w: topW, r: topR), count: sets))
    }

    // MARK: - Building

    @Test func emptyHistoryYieldsEmptyContext() {
        let context = AthleteContext.make(history: [], catalog: catalog, now: now)
        #expect(context.isEmpty)
        #expect(context == .empty)
        #expect(context.promptSection(maxTokens: 500).isEmpty)
    }

    @Test func digestSummarisesLift() throws {
        let bench = exercise(.chest)
        let history = [
            entry(bench.id, daysAgo: 10, topW: 80, topR: 8),
            entry(bench.id, daysAgo: 3, topW: 82.5, topR: 8),
        ]
        let context = AthleteContext.make(history: history, catalog: catalog, now: now)

        let digest = try #require(context.digest(forExId: bench.id))
        #expect(digest.name == bench.name)
        #expect(digest.lastTopWeightKg == 82.5)
        #expect(digest.lastTopReps == 8)
        #expect(digest.currentE1rm == Formulas.e1rmRounded(kg: 82.5, reps: 8))
        #expect(digest.bestE1rm == Formulas.e1rmRounded(kg: 82.5, reps: 8))
        #expect(digest.sessionCount == 2)
        let trend = try #require(digest.trendPercent)
        #expect(trend > 0)
    }

    @Test func singleSessionHasNoTrend() throws {
        let squat = exercise(.quadriceps)
        let context = AthleteContext.make(history: [entry(squat.id, daysAgo: 2, topW: 100, topR: 5)],
                                          catalog: catalog, now: now)
        let digest = try #require(context.digest(forExId: squat.id))
        #expect(digest.trendPercent == nil)
        #expect(digest.promptLine.contains("no trend yet"))
    }

    @Test func staleAndUnknownEntriesAreSkipped() {
        let bench = exercise(.chest)
        let history = [
            entry(bench.id, daysAgo: 90, topW: 80, topR: 8),     // outside the 56-day window
            entry("not-a-real-exercise", daysAgo: 1, topW: 50, topR: 10),
        ]
        let context = AthleteContext.make(history: history, catalog: catalog, now: now)
        #expect(context.isEmpty)
    }

    @Test func liftsOrderedByRelevance() {
        let bench = exercise(.chest)
        let squat = exercise(.quadriceps)
        let history = [
            entry(squat.id, daysAgo: 5, topW: 100, topR: 5),
            entry(bench.id, daysAgo: 12, topW: 80, topR: 8),
            entry(bench.id, daysAgo: 8, topW: 80, topR: 9),
            entry(bench.id, daysAgo: 4, topW: 82.5, topR: 8),
        ]
        let context = AthleteContext.make(history: history, catalog: catalog, now: now)
        #expect(context.lifts.map(\.exId) == [bench.id, squat.id])
    }

    @Test func maxLiftsCapsTheDigest() {
        let chest = catalog.exercises(forMuscle: .chest).prefix(6)
        let history = chest.map { entry($0.id, daysAgo: 1, topW: 40, topR: 10) }
        let context = AthleteContext.make(history: history, catalog: catalog, now: now, maxLifts: 4)
        #expect(context.lifts.count == 4)
    }

    @Test func weeklyVolumeCountsOnlyTrailingSevenDays() {
        let bench = exercise(.chest)
        let history = [
            entry(bench.id, daysAgo: 2, topW: 80, topR: 8, sets: 4),
            entry(bench.id, daysAgo: 6, topW: 80, topR: 8, sets: 3),
            entry(bench.id, daysAgo: 20, topW: 77.5, topR: 8, sets: 5),  // outside the week
        ]
        let context = AthleteContext.make(history: history, catalog: catalog, now: now)
        let chestVolume = context.weeklySetsPerMuscle.first { $0.muscle == .chest }
        #expect(chestVolume?.sets == 7)
    }

    // MARK: - Rendering & budget

    @Test func promptSectionListsLiftsAndVolume() {
        let bench = exercise(.chest)
        let context = AthleteContext.make(history: [entry(bench.id, daysAgo: 2, topW: 82.5, topR: 8)],
                                          catalog: catalog, now: now)
        let section = context.promptSection(maxTokens: 800)
        #expect(section.contains("RECENT LOGGED TRAINING"))
        #expect(section.contains(bench.name))
        #expect(section.contains("82.5 kg × 8"))
        #expect(section.contains("Working sets in the last 7 days"))
        #expect(section.contains("Chest"))
    }

    @Test func promptSectionTrimsToFitBudget() {
        let chest = catalog.exercises(forMuscle: .chest).prefix(10)
        let history = chest.map { entry($0.id, daysAgo: 1, topW: 40, topR: 10) }
        let context = AthleteContext.make(history: history, catalog: catalog, now: now)

        let full = context.promptSection(maxTokens: 10_000)
        let tight = 120
        let trimmed = context.promptSection(maxTokens: tight)

        #expect(PromptBudget.estimatedTokens(full) > tight)
        #expect(!trimmed.isEmpty)
        #expect(PromptBudget.estimatedTokens(trimmed) <= tight)
        #expect(trimmed.count < full.count)
        // The most relevant lift survives trimming.
        #expect(trimmed.contains(context.lifts[0].name))
    }

    @Test func promptSectionEmptyWhenNoBudget() {
        let bench = exercise(.chest)
        let context = AthleteContext.make(history: [entry(bench.id, daysAgo: 2, topW: 80, topR: 8)],
                                          catalog: catalog, now: now)
        #expect(context.promptSection(maxTokens: 0).isEmpty)
    }

    @Test func tokenEstimateIsConservative() {
        let text = String(repeating: "resistance training ", count: 50)  // 1000 chars
        let estimate = PromptBudget.estimatedTokens(text)
        #expect(estimate >= 250)  // never under ~4 chars/token reality
        #expect(PromptBudget.estimatedTokens("") == 0)
    }

    @Test func remainingTokensNeverNegative() {
        let huge = String(repeating: "x", count: 100_000)
        #expect(PromptBudget.remainingTokens(afterFixed: huge) == 0)
        let remaining = PromptBudget.remainingTokens(afterFixed: "short prompt")
        #expect(remaining > 0)
        #expect(remaining < PromptBudget.contextWindow)
    }
}
