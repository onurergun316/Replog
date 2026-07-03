//
//  StallDetectorTests.swift
//  ReplogTests
//
//  Cross-session stall detection (B3): the pure detection rule table (plateau /
//  regression, back-off suppression, deload→swap escalation, bodyweight rep trends),
//  swap-candidate ranking, and the once-per-stall CoachingLog recording path.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct StallDetectorTests {

    private let base = Date(timeIntervalSince1970: 1_750_000_000)
    private let exId = "Barbell_Bench_Press"

    /// One history entry per element, oldest first, spaced 3 days apart from `base`.
    private func history(_ sessions: [(w: Double, r: Int)],
                         exId: String? = nil) -> [HistoryEntry] {
        sessions.enumerated().map { index, s in
            HistoryEntry(exId: exId ?? self.exId,
                         date: base.addingTimeInterval(Double(index) * 3 * 86_400),
                         topW: s.w, topR: s.r,
                         e1rm: Formulas.e1rmRounded(kg: s.w, reps: s.r),
                         sets: [RecordedSet(w: s.w, r: s.r)])
        }
    }

    private func detect(_ sessions: [(w: Double, r: Int)]) -> StallDetection? {
        StallDetector.detect(exId: exId, history: history(sessions))
    }

    // MARK: - Detection: base cases

    @Test func tooLittleHistoryDetectsNothing() {
        #expect(detect([]) == nil)
        #expect(detect([(60, 10)]) == nil)
        #expect(detect([(60, 10), (60, 10)]) == nil)
    }

    @Test func progressingLiftDetectsNothing() {
        #expect(detect([(60, 8), (60, 9), (60, 10), (62.5, 8)]) == nil)
    }

    @Test func singleDipIsNoise() {
        #expect(detect([(60, 9), (60, 10), (60, 8)]) == nil)
    }

    @Test func historyOrderDoesNotMatter() throws {
        let shuffled = history([(60, 10), (60, 10), (60, 10), (60, 10)]).shuffled()
        let stall = try #require(StallDetector.detect(exId: exId, history: shuffled))
        #expect(stall.trend == .plateau)
        #expect(stall.sessionsStalled == 4)
    }

    // MARK: - Detection: plateau & regression

    @Test func flatSessionsArePlateauWithDeload() throws {
        let stall = try #require(detect([(60, 10), (60, 10), (60, 10), (60, 10)]))
        #expect(stall.trend == .plateau)
        #expect(stall.response == .deload)
        #expect(stall.sessionsStalled == 4)
        #expect(stall.stallStartDate == base)
        #expect(stall.lastTopWeightKg == 60)
        #expect(stall.lastTopReps == 10)
    }

    @Test func threeFlatSessionsAreNotYetAPlateau() {
        // Two non-improving deltas — one short of the plateau threshold.
        #expect(detect([(60, 10), (60, 10), (60, 10)]) == nil)
    }

    @Test func repsFallingAtFixedWeightIsRegression() throws {
        let stall = try #require(detect([(100, 10), (100, 9), (100, 8)]))
        #expect(stall.trend == .regression)
        #expect(stall.response == .deload)
        #expect(stall.sessionsStalled == 3)
    }

    @Test func stallStartDateIsTheFirstSessionOfTheRun() throws {
        // Improvement at index 1, then a plateau: the run covers indices 1...4.
        let stall = try #require(detect([(60, 8), (60, 10), (60, 10), (60, 10), (60, 10)]))
        #expect(stall.stallStartDate == base.addingTimeInterval(3 * 86_400))
        #expect(stall.sessionsStalled == 4)
    }

    // MARK: - Detection: back-offs and escalation

    @Test func latestSessionBackoffSuppressesDetection() {
        // The last session dropped the weight 10% — a rebuild in progress, not a stall.
        #expect(detect([(60, 10), (60, 10), (60, 10), (60, 10), (54, 8)]) == nil)
    }

    @Test func newPlateauAfterATriedDeloadEscalatesToSwap() throws {
        // Plateau → deload to 90 → rebuild → stuck at 100 again.
        let stall = try #require(detect([
            (100, 10), (100, 10), (100, 10),
            (90, 10), (95, 10),
            (100, 10), (100, 10), (100, 10), (100, 10),
        ]))
        #expect(stall.trend == .plateau)
        #expect(stall.response == .swapExercise)
        #expect(stall.sessionsStalled == 4)
    }

    @Test func regressionsOwnDropsDoNotCountAsATriedDeload() throws {
        // A mid-run 6% weight drop is part of the regression itself, not a remedy
        // that was already tried — so the first recommendation stays "deload".
        let stall = try #require(detect([(90, 10), (100, 10), (94, 10), (94, 9), (94, 8)]))
        #expect(stall.trend == .regression)
        #expect(stall.response == .deload)
    }

    @Test func backoffOlderThanTheLookbackDoesNotEscalate() throws {
        // A deload 10+ sessions ago is ancient history; recommend a fresh deload.
        var sessions: [(w: Double, r: Int)] = [(100, 10), (90, 10)]
        sessions += (0..<8).map { _ in (95.0, 10) }        // long forgotten rebuild-then-flat
        sessions += [(95, 10)]
        let stall = try #require(detect(sessions))
        #expect(stall.response == .deload)
    }

    // MARK: - Detection: bodyweight lifts

    @Test func bodyweightRepPlateauRecommendsSwap() throws {
        let stall = try #require(detect([(0, 12), (0, 12), (0, 12), (0, 12)]))
        #expect(stall.trend == .plateau)
        #expect(stall.response == .swapExercise)
        #expect(stall.sessionsStalled == 4)
        #expect(stall.lastTopWeightKg == 0)
        #expect(stall.lastTopReps == 12)
    }

    @Test func bodyweightRepRegressionRecommendsSwap() throws {
        let stall = try #require(detect([(0, 12), (0, 11), (0, 10)]))
        #expect(stall.trend == .regression)
        #expect(stall.response == .swapExercise)
    }

    @Test func bodyweightProgressingDetectsNothing() {
        #expect(detect([(0, 10), (0, 11), (0, 12)]) == nil)
    }

    // MARK: - Swap candidates

    private func makeExercise(
        id: String,
        name: String? = nil,
        level: Level = .beginner,
        mechanic: Mechanic? = .compound,
        equipment: Equipment? = .barbell,
        primary: [Muscle] = [.chest]
    ) -> Exercise {
        Exercise(id: id, name: name ?? id, force: .push, level: level, mechanic: mechanic,
                 equipment: equipment, primaryMuscles: primary, secondaryMuscles: [],
                 category: .strength, instructions: [], images: [])
    }

    @Test func swapCandidatesShareEquipmentAndMainMuscleExcludingSelf() {
        let bench = makeExercise(id: "bench")
        let catalog = ExerciseCatalog(exercises: [
            bench,
            makeExercise(id: "incline"),                              // eligible
            makeExercise(id: "flye", mechanic: .isolation),           // eligible, worse rank
            makeExercise(id: "db-press", equipment: .dumbbell),       // wrong equipment
            makeExercise(id: "squat", primary: [.quadriceps]),        // wrong muscle
        ])
        let candidates = StallDetector.swapCandidates(for: bench, catalog: catalog)
        #expect(candidates.map(\.id) == ["incline", "flye"])
    }

    @Test func swapCandidatesRankSimilarityAndRespectTheLimit() {
        let bench = makeExercise(id: "bench", level: .intermediate)
        let catalog = ExerciseCatalog(exercises: [
            bench,
            makeExercise(id: "a-isolation", level: .intermediate, mechanic: .isolation),
            makeExercise(id: "b-compound-other-level", level: .expert),
            makeExercise(id: "c-compound-same-level", level: .intermediate),
            makeExercise(id: "d-compound-same-level-later-name", level: .intermediate),
        ])
        let candidates = StallDetector.swapCandidates(for: bench, catalog: catalog, limit: 2)
        // Same mechanic + same level first (alphabetical within a rank), capped at 2.
        #expect(candidates.map(\.id) == ["c-compound-same-level", "d-compound-same-level-later-name"])
    }

    @Test func bodyweightSwapCandidatesStayBodyweight() {
        let pushup = makeExercise(id: "pushup", equipment: nil)
        let catalog = ExerciseCatalog(exercises: [
            pushup,
            makeExercise(id: "dip", equipment: nil),
            makeExercise(id: "bench", equipment: .barbell),
        ])
        #expect(StallDetector.swapCandidates(for: pushup, catalog: catalog).map(\.id) == ["dip"])
    }

    // MARK: - Recording to the coaching memory

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    /// A tiny catalog whose ids match the histories used below.
    private var testCatalog: ExerciseCatalog {
        ExerciseCatalog(exercises: [
            makeExercise(id: exId, name: "Bench Press"),
            makeExercise(id: "incline", name: "Incline Press"),
        ])
    }

    @discardableResult
    private func record(_ sessions: [(w: Double, r: Int)],
                        into ctx: ModelContext,
                        at date: Date? = nil) -> CoachingLog? {
        let trail = history(sessions)
        return StallDetector.detectAndRecord(
            exId: exId, history: trail, context: ctx, catalog: testCatalog,
            date: date ?? trail.last?.date ?? base)
    }

    @Test func plateauRecordsADeloadLog() throws {
        let ctx = makeContext()
        let log = try #require(record([(60, 10), (60, 10), (60, 10), (60, 10)], into: ctx))
        #expect(log.kind == .deload)
        #expect(log.exId == exId)
        #expect(log.payload.tags.contains("deload"))
        #expect(log.payload.tags.contains("plateau"))
        #expect(log.payload[metric: "sessionsStalled"] == 4)
        #expect(log.payload[metric: "deloadToKg"] == 55)   // 60 × 0.9 snapped to 2.5 kg
        #expect(log.summary.contains("Bench Press"))
        #expect(log.summary.contains("55"))
    }

    @Test func sameOngoingStallIsRecordedOnlyOnce() throws {
        let ctx = makeContext()
        let plateau: [(w: Double, r: Int)] = [(60, 10), (60, 10), (60, 10), (60, 10)]
        _ = try #require(record(plateau, into: ctx))
        // One more stalled session: same stall, same response — no new memory.
        #expect(record(plateau + [(60, 10)], into: ctx) == nil)
        #expect(ctx.coachingLogs().count == 1)
    }

    @Test func escalationToSwapRecordsANewPlateauLog() throws {
        let ctx = makeContext()
        let plateau: [(w: Double, r: Int)] = [(100, 10), (100, 10), (100, 10), (100, 10)]
        _ = try #require(record(plateau, into: ctx))
        let continued = plateau + [(90, 10), (95, 10), (100, 10), (100, 10), (100, 10), (100, 10)]
        let swap = try #require(record(continued, into: ctx))
        #expect(swap.kind == .plateau)
        #expect(swap.payload.tags.contains("swapExercise"))
        #expect(swap.payload.tags.contains("incline"))     // concrete candidate remembered
        #expect(swap.summary.contains("Incline Press"))
        #expect(ctx.coachingLogs().count == 2)
    }

    @Test func aFreshStallAfterRecoveryRecordsAgain() throws {
        let ctx = makeContext()
        let first: [(w: Double, r: Int)] = [(60, 10), (60, 10), (60, 10), (60, 10)]
        _ = try #require(record(first, into: ctx))
        // Recovered (rep PR), then plateaued again at the new level.
        let second = first + [(60, 12), (60, 12), (60, 12), (60, 12)]
        _ = try #require(record(second, into: ctx))
        #expect(ctx.coachingLogs(kind: .deload).count == 2)
    }

    @Test func progressingHistoryRecordsNothing() {
        let ctx = makeContext()
        #expect(record([(60, 8), (60, 9), (60, 10), (60, 11)], into: ctx) == nil)
        #expect(ctx.coachingLogs().isEmpty)
    }

    @Test func unknownExerciseFallsBackToAGenericSummary() throws {
        let ctx = makeContext()
        let trail = history([(60, 10), (60, 10), (60, 10), (60, 10)], exId: "not-in-catalog")
        let log = try #require(StallDetector.detectAndRecord(
            exId: "not-in-catalog", history: trail, context: ctx,
            catalog: testCatalog, date: base))
        #expect(log.summary.hasPrefix("This exercise"))
    }

    @Test func deloadSummaryUsesDisplayUnits() throws {
        let ctx = makeContext()
        ctx.appSettings().units = .lb
        let log = try #require(record([(60, 10), (60, 10), (60, 10), (60, 10)], into: ctx))
        #expect(log.summary.contains("lb"))
    }

    // MARK: - SessionFinisher integration

    @Test func finishingAStalledLiftWritesTheCoachingMemory() throws {
        let ctx = makeContext()
        // Three flat sessions already logged; tonight's identical session makes four.
        for entry in history([(60, 10), (60, 10), (60, 10)]) { ctx.insert(entry) }

        let session = ActiveSession(workoutId: UUID(), name: "Push", planName: "PPL")
        ctx.insert(session)
        let exercise = SessionExercise(exId: exId)
        exercise.session = session
        ctx.insert(exercise)
        let set = LoggedSet(weightKg: 60, reps: 10, rpe: 8, order: 0)
        set.done = true
        set.exercise = exercise
        ctx.insert(set)
        try ctx.save()

        let finishDate = base.addingTimeInterval(9 * 86_400)
        SessionFinisher.finish(session, profile: ctx.userProfile(), context: ctx, date: finishDate)

        let logs = ctx.coachingLogs(kind: .deload)
        #expect(logs.count == 1)
        #expect(logs.first?.exId == exId)
        #expect(logs.first?.date == finishDate)
    }
}
