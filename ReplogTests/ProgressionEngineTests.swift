//
//  ProgressionEngineTests.swift
//  ReplogTests
//
//  The deterministic progression rule table: double progression up the rep range,
//  load increases at the top, holds after a single off day, deloads on regression
//  and plateau, and rep-only progression for bodyweight lifts.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ProgressionEngineTests {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let exId = "Barbell_Bench_Press"
    private let range = 8...12

    /// One history entry per element, oldest first, spaced 3 days apart ending "now".
    private func history(_ sessions: [(w: Double, r: Int)]) -> [HistoryEntry] {
        sessions.enumerated().map { index, s in
            HistoryEntry(exId: exId,
                         date: now.addingTimeInterval(-Double(sessions.count - 1 - index) * 3 * 86_400),
                         topW: s.w, topR: s.r,
                         e1rm: Formulas.e1rmRounded(kg: s.w, reps: s.r),
                         sets: [RecordedSet(w: s.w, r: s.r)])
        }
    }

    private func recommend(_ sessions: [(w: Double, r: Int)],
                           repRange: ClosedRange<Int>? = nil,
                           stepKg: Double = 2.5) -> ProgressionRecommendation? {
        ProgressionEngine.recommend(exId: exId,
                                    history: history(sessions),
                                    repRange: repRange ?? range,
                                    weightStepKg: stepKg)
    }

    // MARK: - Base cases

    @Test func emptyHistoryHasNoRecommendation() {
        #expect(recommend([]) == nil)
    }

    @Test func singleSessionMidRangeAddsARep() throws {
        let rec = try #require(recommend([(60, 10)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedWeightKg == 60)
        #expect(rec.suggestedReps == 11)
        #expect(rec.exId == exId)
    }

    @Test func historyOrderDoesNotMatter() throws {
        let shuffled = history([(60, 8), (60, 9), (60, 10)]).shuffled()
        let rec = try #require(ProgressionEngine.recommend(exId: exId,
                                                           history: shuffled,
                                                           repRange: range))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedReps == 11)
    }

    // MARK: - Progressing histories

    @Test func progressingBelowRangeTopAddsARep() throws {
        let rec = try #require(recommend([(60, 8), (60, 9), (60, 10)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedWeightKg == 60)
        #expect(rec.suggestedReps == 11)
        #expect(rec.reason.contains("Progressing"))
    }

    @Test func hittingRangeTopIncreasesLoadAndResetsReps() throws {
        let rec = try #require(recommend([(60, 10), (60, 11), (60, 12)]))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg == 62.5)
        #expect(rec.suggestedReps == range.lowerBound)
        #expect(rec.reason.contains("62.5kg"))
    }

    @Test func exceedingRangeTopAlsoIncreasesLoad() throws {
        let rec = try #require(recommend([(60, 14)]))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg == 62.5)
    }

    @Test func rangeTopBeatsARegressingTrail() throws {
        // e1RM regressed two sessions in a row (93 → 89 → 84), but the lifter reached
        // the range top at the lighter weight — success now wins over the trend.
        let rec = try #require(recommend([(70, 10), (65, 11), (60, 12)]))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg == 62.5)
    }

    @Test func repsBelowRangeFloorAreLiftedToTheFloor() throws {
        let rec = try #require(recommend([(60, 5), (60, 6)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedReps == range.lowerBound)
    }

    // MARK: - Off days and stalls

    @Test func singleDownSessionHolds() throws {
        let rec = try #require(recommend([(60, 10), (60, 8)]))
        #expect(rec.action == .hold)
        #expect(rec.suggestedWeightKg == 60)
        #expect(rec.suggestedReps == 8)
        #expect(rec.reason.contains("dipped"))
    }

    @Test func twoConsecutiveDropsDeload() throws {
        let rec = try #require(recommend([(60, 10), (60, 9), (60, 8)]))
        #expect(rec.action == .deload)
        // 90% of 60 = 54, snapped to 2.5 → 55, strictly below 60.
        #expect(rec.suggestedWeightKg == 55)
        #expect(rec.suggestedReps == range.lowerBound)
        #expect(rec.reason.contains("dropped"))
    }

    @Test func flatPlateauAcrossFourSessionsDeloads() throws {
        let rec = try #require(recommend([(60, 10), (60, 10), (60, 10), (60, 10)]))
        #expect(rec.action == .deload)
        #expect(rec.suggestedWeightKg == 55)
        #expect(rec.reason.contains("No progress"))
    }

    @Test func shortFlatStretchKeepsPushingReps() throws {
        // Only two flat deltas (three sessions) — not yet a plateau.
        let rec = try #require(recommend([(60, 10), (60, 10), (60, 10)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedReps == 11)
    }

    @Test func recoveryAfterADipIsNotARegression() throws {
        let rec = try #require(recommend([(60, 10), (60, 8), (60, 10)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedReps == 11)
    }

    // MARK: - Bodyweight lifts

    @Test func bodyweightProgressesByRepsPastTheRangeTop() throws {
        let rec = try #require(recommend([(0, 12), (0, 14)]))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedWeightKg == 0)
        #expect(rec.suggestedReps == 15)
    }

    @Test func bodyweightStallHoldsInsteadOfDeloading() throws {
        let rec = try #require(recommend([(0, 12), (0, 11), (0, 10)]))
        #expect(rec.action == .hold)
        #expect(rec.suggestedWeightKg == 0)
        #expect(rec.suggestedReps == 10)
    }

    // MARK: - Deload math

    @Test func deloadSnapsToTheWeightStep() {
        #expect(ProgressionEngine.deloadWeight(fromKg: 60, stepKg: 2.5) == 55)
        #expect(ProgressionEngine.deloadWeight(fromKg: 100, stepKg: 2.5) == 90)
        #expect(ProgressionEngine.deloadWeight(fromKg: 60, stepKg: Formulas.lbToKg(5)) ==
                (60 * 0.9 / Formulas.lbToKg(5)).rounded() * Formulas.lbToKg(5))
    }

    @Test func deloadIsAlwaysStrictlyBelowTheCurrentWeight() {
        for kg in stride(from: 2.5, through: 200, by: 2.5) {
            let deload = ProgressionEngine.deloadWeight(fromKg: kg, stepKg: 2.5)
            #expect(deload < kg)
            #expect(deload >= 0)
        }
    }

    @Test func deloadWithoutAStepUsesTheRawTarget() {
        #expect(ProgressionEngine.deloadWeight(fromKg: 60, stepKg: 0) == 54)
        #expect(ProgressionEngine.deloadWeight(fromKg: 0, stepKg: 2.5) == 0)
    }

    // MARK: - Goal contract & units

    @Test func repRangesBracketTheGeneratorPrescription() {
        // PlanGenerator prescribes 10 / 13 / 8 reps — each range must contain its goal's value.
        #expect(ProgressionEngine.repRange(for: .buildMuscle).contains(10))
        #expect(ProgressionEngine.repRange(for: .recomp).contains(10))
        #expect(ProgressionEngine.repRange(for: .loseWeight).contains(13))
        #expect(ProgressionEngine.repRange(for: .sport).contains(8))
    }

    @Test func goalConvenienceUsesGoalRangeAndUnitStep() throws {
        // Fat-loss range tops out at 15: 15 reps at 60 kg triggers a load increase.
        let rec = try #require(ProgressionEngine.recommend(exId: exId,
                                                           history: history([(60, 15)]),
                                                           goal: .loseWeight))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg == 62.5)
        #expect(rec.suggestedReps == 12)
    }

    @Test func lbUnitsStepByFivePoundsAndFormatReasonsInLb() throws {
        let rec = try #require(ProgressionEngine.recommend(exId: exId,
                                                           history: history([(60, 12)]),
                                                           goal: .buildMuscle,
                                                           units: .lb))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg == 60 + Formulas.lbToKg(5))
        #expect(rec.reason.contains("lb"))
        #expect(!rec.reason.contains("kg"))
    }

    // MARK: - First-session RPE calibration (opt-in via targetRPE)

    private func entryRPE(_ w: Double, _ r: Int, _ rpe: Int, daysAgo: Double) -> HistoryEntry {
        HistoryEntry(exId: exId, date: now.addingTimeInterval(-daysAgo * 86_400),
                     topW: w, topR: r, e1rm: Formulas.e1rmRounded(kg: w, reps: r),
                     sets: [RecordedSet(w: w, r: r)], topRPE: rpe)
    }

    @Test func firstSessionOverSeededAtHighRPECalibratesLoadDown() throws {
        // Seeded 80 kg × 8 but it felt like RPE 10 vs a target of 8 → drop the load.
        let rec = try #require(ProgressionEngine.recommend(
            exId: exId, history: [entryRPE(80, 8, 10, daysAgo: 0)],
            goal: .buildMuscle, targetRPE: 8))
        #expect(rec.action == .deload)
        #expect(rec.suggestedWeightKg < 80)
        #expect(rec.suggestedWeightKg == 75)   // e1RM 101.3 → working at 8@8 → 75
        #expect(rec.reason.contains("Calibrated"))
    }

    @Test func firstSessionUnderSeededAtLowRPECalibratesLoadUp() throws {
        let rec = try #require(ProgressionEngine.recommend(
            exId: exId, history: [entryRPE(40, 8, 5, daysAgo: 0)],
            goal: .buildMuscle, targetRPE: 8))
        #expect(rec.action == .increaseLoad)
        #expect(rec.suggestedWeightKg > 40)
    }

    @Test func withoutTargetRPETheFirstSessionRuleIsUnchanged() throws {
        // No targetRPE → the existing double-progression behavior (add a rep) is preserved.
        let rec = try #require(ProgressionEngine.recommend(
            exId: exId, history: [entryRPE(80, 8, 10, daysAgo: 0)], goal: .buildMuscle))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedWeightKg == 80)
    }

    @Test func onTargetRPEDoesNotTriggerCalibration() throws {
        // Felt exactly like the target → normal rules apply (no calibration override).
        let rec = try #require(ProgressionEngine.recommend(
            exId: exId, history: [entryRPE(60, 10, 8, daysAgo: 0)], goal: .buildMuscle, targetRPE: 8))
        #expect(rec.action == .increaseReps)
        #expect(rec.suggestedWeightKg == 60)
    }

    @Test func calibrationAppliesOnlyToTheFirstSession() throws {
        // Two sessions → calibration is skipped; normal progression drives the result.
        let rec = try #require(ProgressionEngine.recommend(
            exId: exId,
            history: [entryRPE(80, 8, 10, daysAgo: 3), entryRPE(80, 9, 10, daysAgo: 0)],
            goal: .buildMuscle, targetRPE: 8))
        #expect(rec.suggestedWeightKg == 80)   // not calibrated down to 75
    }
}
