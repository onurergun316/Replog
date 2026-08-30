//
//  CoachingLogTests.swift
//  ReplogTests
//
//  The coaching memory store (A3): CoachingLog persistence, typed accessors,
//  JSON payload round-trips, the ReplogStore fetch/record helpers, and the
//  "memory outlives the plan" reference-not-relationship rule.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct CoachingLogTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    // MARK: - Model

    @Test func kindRoundTripsThroughRawValue() {
        let log = CoachingLog(kind: .plateau, summary: "Bench stalled 3 weeks")
        #expect(log.kind == .plateau)
        #expect(log.kindRaw == "plateau")
        log.kind = .deload
        #expect(log.kindRaw == "deload")
    }

    @Test func unknownKindRawFallsBackToNote() {
        let log = CoachingLog(kind: .note, summary: "x")
        log.kindRaw = "not-a-kind"
        #expect(log.kind == .note)
    }

    @Test func freshLogHasEmptyPayload() {
        let log = CoachingLog(kind: .note, summary: "x")
        #expect(log.payload.metrics.isEmpty)
        #expect(log.payload.tags.isEmpty)
    }

    @Test func barePayloadJSONDecodesToEmpty() {
        // The model's default `payloadJSON` ("{}") must decode leniently, not fall back.
        let payload = try? JSONDecoder().decode(CoachingPayload.self, from: Data("{}".utf8))
        #expect(payload?.metrics.isEmpty == true)
        #expect(payload?.tags.isEmpty == true)
    }

    @Test func payloadRoundTripsThroughJSON() {
        let payload = CoachingPayload(
            metrics: ["fromWeightKg": 60, "toWeightKg": 62.5, "trendPct": 4.1],
            tags: ["increaseLoad", "chest"]
        )
        let log = CoachingLog(kind: .progression, summary: "Up 2.5 kg", exId: "Barbell_Bench_Press", payload: payload)
        #expect(log.payload[metric: "toWeightKg"] == 62.5)
        #expect(log.payload.tags == ["increaseLoad", "chest"])
        #expect(log.payload[metric: "missing"] == nil)
        // Mutating via the computed setter re-encodes.
        log.payload = CoachingPayload(metrics: ["bodyweightKg": 82.3])
        #expect(log.payload[metric: "bodyweightKg"] == 82.3)
        #expect(log.payload.tags.isEmpty)
    }

    @Test func payloadSurvivesSaveAndFetch() throws {
        let ctx = makeContext()
        let log = CoachingLog(kind: .bodyweight, summary: "Weekly check-in",
                              payload: CoachingPayload(metrics: ["bodyweightKg": 79.0], tags: ["down"]))
        ctx.insert(log)
        try ctx.save()

        let fetched = try #require(try ctx.fetch(FetchDescriptor<CoachingLog>()).first)
        #expect(fetched.kind == .bodyweight)
        #expect(fetched.payload[metric: "bodyweightKg"] == 79.0)
        #expect(fetched.payload.tags == ["down"])
    }

    // MARK: - Store helpers

    @Test func recordCoachingInsertsAndReturnsLog() throws {
        let ctx = makeContext()
        let log = ctx.recordCoaching(.note, summary: "Great session today")
        try ctx.save()

        #expect(log.summary == "Great session today")
        #expect(try ctx.fetch(FetchDescriptor<CoachingLog>()).count == 1)
    }

    @Test func coachingLogsAreNewestFirst() throws {
        let ctx = makeContext()
        let now = Date()
        ctx.recordCoaching(.note, summary: "old", date: now.addingTimeInterval(-2000))
        ctx.recordCoaching(.note, summary: "new", date: now)
        ctx.recordCoaching(.note, summary: "mid", date: now.addingTimeInterval(-1000))
        try ctx.save()

        #expect(ctx.coachingLogs().map(\.summary) == ["new", "mid", "old"])
    }

    @Test func coachingLogsFilterByKind() throws {
        let ctx = makeContext()
        ctx.recordCoaching(.progression, summary: "p1")
        ctx.recordCoaching(.plateau, summary: "s1")
        ctx.recordCoaching(.progression, summary: "p2")
        try ctx.save()

        #expect(ctx.coachingLogs(kind: .progression).count == 2)
        #expect(ctx.coachingLogs(kind: .plateau).map(\.summary) == ["s1"])
        #expect(ctx.coachingLogs(kind: .deload).isEmpty)
    }

    @Test func coachingLogsRespectLimit() throws {
        let ctx = makeContext()
        let now = Date()
        for i in 0..<5 {
            ctx.recordCoaching(.note, summary: "n\(i)", date: now.addingTimeInterval(Double(i)))
        }
        try ctx.save()

        let two = ctx.coachingLogs(limit: 2)
        #expect(two.count == 2)
        #expect(two.map(\.summary) == ["n4", "n3"]) // newest first
    }

    @Test func latestCoachingLogReturnsMostRecentOfKind() throws {
        let ctx = makeContext()
        let now = Date()
        ctx.recordCoaching(.weeklyReport, summary: "week 1", date: now.addingTimeInterval(-604_800))
        ctx.recordCoaching(.weeklyReport, summary: "week 2", date: now)
        ctx.recordCoaching(.monthlyReport, summary: "month", date: now)
        try ctx.save()

        #expect(ctx.latestCoachingLog(kind: .weeklyReport)?.summary == "week 2")
        #expect(ctx.latestCoachingLog(kind: .deload) == nil)
    }

    @Test func coachingLogsForExerciseFilterAndSort() throws {
        let ctx = makeContext()
        let now = Date()
        ctx.recordCoaching(.progression, summary: "bench old", date: now.addingTimeInterval(-1000), exId: "A")
        ctx.recordCoaching(.progression, summary: "bench new", date: now, exId: "A")
        ctx.recordCoaching(.progression, summary: "squat", date: now, exId: "B")
        try ctx.save()

        let a = ctx.coachingLogs(forExercise: "A")
        #expect(a.map(\.summary) == ["bench new", "bench old"]) // newest first
    }

    // MARK: - "Memory outlives the plan" (reference, not relationship)

    @Test func coachingLogSurvivesPlanDeletion() throws {
        let ctx = makeContext()
        let plan = Plan(name: "PPL", order: 0)
        ctx.insert(plan)
        let planId = plan.id
        ctx.recordCoaching(.planAdjustment, summary: "Swapped in RDLs", planId: planId)
        try ctx.save()

        ctx.delete(plan)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Plan>()).isEmpty)
        let logs = ctx.coachingLogs()
        #expect(logs.count == 1)
        // The memory persists and still points at the (now-deleted) plan's id — no cascade.
        #expect(logs.first?.planId == planId)
    }

    @Test func deletingLogLeavesUnrelatedDataIntact() throws {
        let ctx = makeContext()
        let plan = Plan(name: "P", order: 0)
        ctx.insert(plan)
        let log = ctx.recordCoaching(.note, summary: "temp")
        try ctx.save()

        ctx.delete(log)
        try ctx.save()

        #expect(ctx.coachingLogs().isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Plan>()).count == 1) // untouched
    }

    // MARK: Kind identity & copy

    @Test func everyCoachingKindHasAnIdentityAndADisplayName() {
        for kind in CoachingKind.allCases {
            #expect(kind.id == kind.rawValue)
            #expect(!kind.displayName.isEmpty)
        }
        #expect(CoachingKind.weeklyReport.displayName == "Weekly report")
        #expect(CoachingKind.coachInsight.displayName == "Coach")
    }

    @Test func aPayloadMetricIsReadableBySubscript() {
        let payload = CoachingPayload(metrics: ["prCount": 2], tags: [])
        #expect(payload[metric: "prCount"] == 2)
        #expect(payload[metric: "missing"] == nil)
    }
}
