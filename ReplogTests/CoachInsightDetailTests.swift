//
//  CoachInsightDetailTests.swift
//  ReplogTests
//
//  Opening up a recorded insight. The payload is a dictionary of raw keys and a mixed bag
//  of tags, and the sheet built from it has to be stable and readable: same order every
//  time, catalog ids resolved to lift names, the insight's own kind not repeated back as
//  a chip.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct CoachInsightDetailTests {

    private func detail(kind: CoachInsightKind = .sessionDebrief,
                        title: String = "Session complete",
                        body: String = "Total volume 8180kg.",
                        exId: String? = nil,
                        metrics: [String: Double] = [:],
                        tags: [String] = [],
                        units: Units = .kg,
                        names: [String: String] = [:]) -> CoachInsightDetail {
        CoachInsightDetail.make(kind: kind, title: title, body: body, date: Date(),
                                exId: exId,
                                payload: CoachingPayload(metrics: metrics, tags: tags),
                                units: units, name: { names[$0] })
    }

    // MARK: - The numbers behind the insight

    @Test func knownMetricsAreLabelledAndOrdered() {
        // Handed over in an order the display must not inherit.
        let facts = detail(metrics: ["weeklyRateKg": 0.4, "workoutStreak": 5,
                                     "prCount": 2, "totalVolumeKg": 8180]).facts

        #expect(facts.map(\.label) == ["Personal bests", "Session volume",
                                       "Workout streak", "Weekly change"])
        #expect(facts.map(\.value) == ["2", "8180kg", "5 days", "+0.4kg"])
    }

    @Test func theSameMetricsAlwaysReadInTheSameOrder() {
        let metrics: [String: Double] = ["prCount": 1, "totalVolumeKg": 100,
                                         "sessionsStalled": 4, "lastE1RM": 93]
        let first = detail(metrics: metrics).facts.map(\.label)
        // Dictionary iteration order is not stable between instances; the output must be.
        for _ in 0..<20 {
            #expect(detail(metrics: metrics).facts.map(\.label) == first)
        }
    }

    @Test func weightsFollowTheAthletesUnits() {
        let kg = detail(metrics: ["totalVolumeKg": 100], units: .kg).facts.first
        let lb = detail(metrics: ["totalVolumeKg": 100], units: .lb).facts.first

        #expect(kg?.value == "100kg")
        // Bar weights round to the nearest 5 lb — plate math, per `Formulas.kgToLb`.
        #expect(lb?.value == "220lb")
    }

    @Test func aRateReadsAsADirection() {
        #expect(detail(metrics: ["weeklyRateKg": 0.4]).facts.first?.value == "+0.4kg")
        #expect(detail(metrics: ["weeklyRateKg": -0.4]).facts.first?.value == "−0.4kg")
        #expect(detail(metrics: ["weeklyRateKg": 0]).facts.first?.value == "0kg")
    }

    @Test func countsAreSingularWhenTheyAreOne() {
        #expect(detail(metrics: ["workoutStreak": 1]).facts.first?.value == "1 day")
        #expect(detail(metrics: ["workoutStreak": 2]).facts.first?.value == "2 days")
        #expect(detail(metrics: ["sessionsStalled": 1]).facts.first?.value == "1 session")
        #expect(detail(metrics: ["programWeeks": 6]).facts.first?.value == "6 weeks")
        #expect(detail(metrics: ["lastTopReps": 8]).facts.first?.value == "8 reps")
        #expect(detail(metrics: ["patternDays": 3]).facts.first?.value == "3 days")
    }

    @Test func anUnknownMetricStillReadsAsSomething() {
        // A metric added after this formatter was written must not vanish or crash it.
        let facts = detail(metrics: ["prCount": 1, "someNewMetric": 12.5]).facts

        #expect(facts.map(\.label) == ["Personal bests", "Some New Metric"])
        #expect(facts.last?.value == "12.5")
    }

    @Test func unknownMetricsSortAlphabeticallyAfterTheKnownOnes() {
        let facts = detail(metrics: ["zeta": 1, "alpha": 2, "prCount": 3]).facts
        #expect(facts.map(\.label) == ["Personal bests", "Alpha", "Zeta"])
    }

    @Test func noMetricsMeansNoFacts() {
        #expect(detail().facts.isEmpty)
        #expect(!detail().hasSupportingDetail)
    }

    // MARK: - Tags

    @Test func exerciseIdTagsBecomeLiftNames() {
        let result = detail(tags: ["Seated_Dumbbell_Curl", "Reverse_Flyes"],
                            names: ["Seated_Dumbbell_Curl": "Seated Dumbbell Curl",
                                    "Reverse_Flyes": "Reverse Flyes"])

        #expect(result.exercises == ["Seated Dumbbell Curl", "Reverse Flyes"])
        #expect(result.notes.isEmpty)
        #expect(result.hasSupportingDetail)
    }

    @Test func theInsightsOwnKindIsNotRepeatedBackAsAChip() {
        // `CoachContextBuilder.record` appends the kind to the tags; it is already the title.
        let result = detail(kind: .milestone, tags: ["milestone", "deload"])

        #expect(result.notes == ["Deload"])
        #expect(result.exercises.isEmpty)
    }

    @Test func aPlainTagIsMadeReadable() {
        let result = detail(tags: ["swapExercise", "regression"])
        #expect(result.notes == ["Swap Exercise", "Regression"])
    }

    @Test func theSubjectLiftLeadsAndIsNotRepeated() {
        let result = detail(exId: "Bench", tags: ["Bench", "deload"],
                            names: ["Bench": "Barbell Bench Press"])

        #expect(result.exercises == ["Barbell Bench Press"])
        #expect(result.notes == ["Deload"])
    }

    @Test func anExerciseTheCatalogNoLongerKnowsStillReads() {
        // History outlives the catalog: a deleted custom exercise must not print raw.
        let result = detail(exId: "Custom_Zercher_Squat")
        #expect(result.exercises == ["Custom Zercher Squat"])
    }

    @Test func duplicateTagsAppearOnce() {
        let result = detail(tags: ["deload", "deload", "Bench", "Bench"],
                            names: ["Bench": "Bench Press"])
        #expect(result.notes == ["Deload"])
        #expect(result.exercises == ["Bench Press"])
    }

    // MARK: - Readable tokens

    @Test func readableHandlesTheTokenShapesTheAppStores() {
        #expect(CoachInsightDetail.readable("deload") == "Deload")
        #expect(CoachInsightDetail.readable("swapExercise") == "Swap Exercise")
        #expect(CoachInsightDetail.readable("Seated_Dumbbell_Curl") == "Seated Dumbbell Curl")
        #expect(CoachInsightDetail.readable("") == "")
    }

    // MARK: - The bridge from the store

    @Test func aRecordedLogReadsBackAsItWasWritten() throws {
        let ctx = ModelContext(ReplogSchema.inMemoryContainer())
        let insight = CoachInsight(kind: .milestone, priority: .high,
                                   title: "2 new personal bests!",
                                   body: "You hit a new estimated-1RM best.",
                                   exId: "Bench",
                                   metrics: ["prCount": 2], tags: ["Bench"])
        let log = CoachContextBuilder.recordDailyCard(insight, context: ctx)
        try? ctx.save()

        let recorded = try #require(log)
        let read = recorded.detail(units: .kg, catalog: .shared)

        #expect(read.kind == .milestone)
        #expect(read.title == "2 new personal bests!")
        #expect(read.body == "You hit a new estimated-1RM best.")
        #expect(read.facts == [CoachInsightDetail.Fact(label: "Personal bests", value: "2")])
        // The kind rides in the tags and must not surface as a chip.
        #expect(!read.notes.contains("Milestone"))
    }
}
