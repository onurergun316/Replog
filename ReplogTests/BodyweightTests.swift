//
//  BodyweightTests.swift
//  ReplogTests
//
//  The bodyweight check-in (C1): store helpers (log/upsert/order), the pure
//  BodyweightTracker (due logic, snapshot trend math, goal sentiment), and the
//  0.1-precision bodyweight display formulas.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct BodyweightTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    private func day(_ offset: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    /// Entries at daily offsets (relative to now) with the given weights.
    private func entries(_ points: [(offset: Int, kg: Double)]) -> [BodyweightEntry] {
        points.map { BodyweightEntry(weightKg: $0.kg, date: day($0.offset)) }
    }

    // MARK: - Store helpers

    @Test func logInsertsAndFetchesOldestFirst() throws {
        let ctx = makeContext()
        ctx.logBodyweight(78, date: day(-14))
        ctx.logBodyweight(77, date: day(-7))
        ctx.logBodyweight(76.5, date: day(0))
        try ctx.save()

        let all = ctx.bodyweightEntries()
        #expect(all.map(\.weightKg) == [78, 77, 76.5])
        #expect(ctx.latestBodyweight()?.weightKg == 76.5)
    }

    @Test func sameDayLogUpdatesInsteadOfDuplicating() throws {
        let ctx = makeContext()
        let morning = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        ctx.logBodyweight(77.8, date: morning)
        let updated = ctx.logBodyweight(77.2, date: morning.addingTimeInterval(3600))
        try ctx.save()

        let all = ctx.bodyweightEntries()
        #expect(all.count == 1)
        #expect(all.first?.weightKg == 77.2)
        #expect(updated.weightKg == 77.2)
    }

    @Test func differentDaysCreateSeparateEntries() throws {
        let ctx = makeContext()
        ctx.logBodyweight(78, date: day(-1))
        ctx.logBodyweight(77.5, date: day(0))
        try ctx.save()
        #expect(ctx.bodyweightEntries().count == 2)
    }

    @Test func entriesPersistAcrossContexts() throws {
        let container = ReplogSchema.inMemoryContainer()
        let ctx = ModelContext(container)
        ctx.logBodyweight(80.3, date: day(-2))
        try ctx.save()

        let fresh = ModelContext(container)
        #expect(fresh.latestBodyweight()?.weightKg == 80.3)
    }

    @Test func latestBodyweightIsNilOnEmptyStore() {
        #expect(makeContext().latestBodyweight() == nil)
    }

    // MARK: - Check-in due

    @Test func dueWhenNeverLogged() {
        #expect(BodyweightTracker.checkInDue(lastDate: nil))
    }

    @Test func notDueRightAfterLogging() {
        #expect(!BodyweightTracker.checkInDue(lastDate: Date()))
        #expect(!BodyweightTracker.checkInDue(lastDate: day(-3)))
    }

    @Test func dueAfterTheInterval() {
        #expect(BodyweightTracker.checkInDue(lastDate: day(-BodyweightTracker.checkInIntervalDays)))
        #expect(BodyweightTracker.checkInDue(lastDate: day(-10)))
        #expect(!BodyweightTracker.checkInDue(lastDate: day(-(BodyweightTracker.checkInIntervalDays - 1))))
    }

    // MARK: - Snapshot

    @Test func emptySeriesHasNoSnapshot() {
        #expect(BodyweightTracker.snapshot(entries: []) == nil)
    }

    @Test func singleEntrySnapshotHasNoTrendYet() throws {
        let snap = try #require(BodyweightTracker.snapshot(entries: entries([(0, 76.5)])))
        #expect(snap.currentKg == 76.5)
        #expect(snap.deltaKg == nil)
        #expect(snap.weeklyRateKg == nil)
        #expect(snap.direction == Trend.none)
        #expect(snap.sparklineValues == [765])
    }

    @Test func decreasingSeriesTrendsDown() throws {
        // 0.5 kg lost per week over five weekly check-ins.
        let snap = try #require(BodyweightTracker.snapshot(
            entries: entries([(-28, 78), (-21, 77.5), (-14, 77), (-7, 76.5), (0, 76)])))
        #expect(snap.currentKg == 76)
        #expect(snap.deltaKg == -0.5)
        let rate = try #require(snap.weeklyRateKg)
        #expect(abs(rate - (-0.5)) < 0.01)
        #expect(snap.direction == .down)
    }

    @Test func increasingSeriesTrendsUp() throws {
        let snap = try #require(BodyweightTracker.snapshot(
            entries: entries([(-14, 70), (-7, 70.6), (0, 71.2)])))
        #expect(snap.direction == .up)
        #expect(snap.deltaKg == 71.2 - 70.6)
    }

    @Test func scaleNoiseWithinDeadbandIsFlat() throws {
        // ±0.1 kg wobble around 75 — a real scale never repeats exactly.
        let snap = try #require(BodyweightTracker.snapshot(
            entries: entries([(-21, 75.1), (-14, 74.9), (-7, 75.1), (0, 75.0)])))
        #expect(snap.direction == .flat)
    }

    @Test func snapshotIsOrderInvariant() throws {
        let series = entries([(-14, 77), (0, 76), (-7, 76.5), (-21, 77.5)])
        let snap = try #require(BodyweightTracker.snapshot(entries: series))
        #expect(snap.currentKg == 76)
        #expect(snap.deltaKg == -0.5)
        #expect(snap.direction == .down)
    }

    @Test func rateIgnoresEntriesOlderThanTheWindow() throws {
        // An ancient 90 kg entry must not steepen the recent, gentle trend.
        let snap = try #require(BodyweightTracker.snapshot(
            entries: entries([(-200, 90), (-14, 75.4), (-7, 75.2), (0, 75.0)])))
        let rate = try #require(snap.weeklyRateKg)
        #expect(abs(rate - (-0.2)) < 0.01)
        #expect(snap.direction == .down)
    }

    @Test func onlyOldHistoryPlusOneRecentEntryHasNoRate() throws {
        // The single in-window entry can't make a slope; direction stays .none.
        let snap = try #require(BodyweightTracker.snapshot(
            entries: entries([(-100, 80), (0, 76)])))
        #expect(snap.weeklyRateKg == nil)
        #expect(snap.direction == Trend.none)
        // But the delta vs the previous check-in still reads.
        #expect(snap.deltaKg == -4)
    }

    @Test func sparklineKeepsOnlyTheRecentPoints() throws {
        let series = (0..<20).map { i in
            BodyweightEntry(weightKg: 80 - Double(i) * 0.1, date: day(i - 20))
        }
        let snap = try #require(BodyweightTracker.snapshot(entries: series))
        #expect(snap.sparklineValues.count == BodyweightTracker.sparklinePoints)
        // Oldest-first and ending at the newest weight.
        #expect(snap.sparklineValues.last == Int((snap.currentKg * 10).rounded()))
        #expect(snap.sparklineValues.first! > snap.sparklineValues.last!)
    }

    // MARK: - Goal sentiment

    @Test func trendFavorabilityFollowsTheGoal() {
        #expect(BodyweightTracker.isFavorable(.up, for: .buildMuscle) == true)
        #expect(BodyweightTracker.isFavorable(.down, for: .buildMuscle) == false)
        #expect(BodyweightTracker.isFavorable(.down, for: .loseWeight) == true)
        #expect(BodyweightTracker.isFavorable(.up, for: .loseWeight) == false)
        #expect(BodyweightTracker.isFavorable(.up, for: .recomp) == nil)
        #expect(BodyweightTracker.isFavorable(.down, for: .sport) == nil)
        #expect(BodyweightTracker.isFavorable(.flat, for: .loseWeight) == nil)
        #expect(BodyweightTracker.isFavorable(.none, for: .buildMuscle) == nil)
    }

    // MARK: - Display formulas

    @Test func bodyweightDisplayKeepsTenthPrecisionInPounds() {
        // Bar weights round lb to the nearest 5; the scale must not.
        #expect(Formulas.displayBodyweight(kg: 76.5, units: .lb) == 168.7)
        #expect(Formulas.displayBodyweight(kg: 76.5, units: .kg) == 76.5)
        #expect(Formulas.kgToLb(76.5) == 170)   // the coarse bar-weight path, unchanged
    }

    @Test func bodyweightFormattingDropsTrailingZero() {
        #expect(Formulas.formatBodyweight(kg: 76.5, units: .kg) == "76.5kg")
        #expect(Formulas.formatBodyweight(kg: 76.0, units: .kg) == "76kg")
        #expect(Formulas.formatBodyweight(kg: 76.5, units: .lb) == "168.7lb")
        #expect(Formulas.formatBodyweight(kg: 76.5, units: .kg, includeUnit: false) == "76.5")
    }

    @Test func bodyweightStepMatchesTheDisplayUnit() {
        #expect(Formulas.bodyweightStepKg(units: .kg) == 0.5)
        // ±1 lb expressed in kg.
        #expect(abs(Formulas.bodyweightStepKg(units: .lb) - 0.4536) < 0.001)
    }
}
