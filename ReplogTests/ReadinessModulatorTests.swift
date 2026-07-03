//
//  ReadinessModulatorTests.swift
//  ReplogTests
//
//  The pure readiness → modulation table, reason strings, and weekly pattern detection.
//

import Testing
import Foundation
@testable import Replog

struct ReadinessModulatorTests {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - Modulation table

    @Test func freshOrLightFatigueTrainsAsPlanned() {
        #expect(ReadinessModulator.modulation(for: .fresh) == .normal)
        // Load 1 (one moderate) is still normal.
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .good, soreness: .moderate, stress: .good)) == .normal)
    }

    @Test func moderateFatigueCapsIntensity() {
        // Load 2 and 3 → cap intensity (keep volume).
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)) == .capIntensity)
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .moderate, soreness: .moderate, stress: .good)) == .capIntensity)
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .poor, soreness: .moderate, stress: .good)) == .capIntensity)
    }

    @Test func highFatigueTrimsTheLastSet() {
        // Load ≥ 4 → trim last set.
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .good)) == .trimLastSet)
        #expect(ReadinessModulator.modulation(for:
            ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .poor)) == .trimLastSet)
    }

    @Test func onlyTrimReducesVolume() {
        #expect(SessionModulation.trimLastSet.reducesVolume)
        #expect(!SessionModulation.capIntensity.reducesVolume)
        #expect(!SessionModulation.normal.reducesVolume)
    }

    // MARK: - Reason strings

    @Test func reasonIsEmptyForNormalNamesDimensionsOtherwise() {
        #expect(ReadinessModulator.reason(for: .fresh, modulation: .normal).isEmpty)

        let poorSleep = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)
        let capReason = ReadinessModulator.reason(for: poorSleep, modulation: .capIntensity)
        #expect(capReason.contains("poor sleep"))
        #expect(capReason.contains("Capped intensity"))

        let wrecked = ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .good)
        let trimReason = ReadinessModulator.reason(for: wrecked, modulation: .trimLastSet)
        #expect(trimReason.contains("Trimmed a set"))
        #expect(trimReason.contains("poor sleep"))
        #expect(trimReason.contains("high soreness"))
    }

    @Test func reasonLeadsWithThePoorestSignal() {
        // Moderate soreness + poor stress → the poor one is named first.
        let c = ReadinessCheckIn(sleep: .good, soreness: .moderate, stress: .poor)
        let reason = ReadinessModulator.reason(for: c, modulation: .trimLastSet)
        let stressIdx = reason.range(of: "high stress")?.lowerBound
        let soreIdx = reason.range(of: "some soreness")?.lowerBound
        #expect(stressIdx != nil && soreIdx != nil)
        if let s = stressIdx, let so = soreIdx { #expect(s < so) }
    }

    // MARK: - Pattern detection

    @Test func threeLowSleepDaysThisWeekIsAPattern() throws {
        let poorSleep = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)
        let ratings = Array(repeating: poorSleep, count: 3)
        let dates = [now.addingTimeInterval(-1 * 86_400),
                     now.addingTimeInterval(-2 * 86_400),
                     now.addingTimeInterval(-3 * 86_400)]
        let pattern = try #require(ReadinessModulator.recentPattern(ratings: ratings, forDates: dates, now: now))
        #expect(pattern == .lowSleep(days: 3))
    }

    @Test func twoDaysIsNotYetAPattern() {
        let poorSleep = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)
        let ratings = Array(repeating: poorSleep, count: 2)
        let dates = [now.addingTimeInterval(-1 * 86_400), now.addingTimeInterval(-2 * 86_400)]
        #expect(ReadinessModulator.recentPattern(ratings: ratings, forDates: dates, now: now) == nil)
    }

    @Test func staleDaysOutsideTheWindowDoNotCount() {
        let poorSleep = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)
        // Two recent + one 10 days old → only two in-window, not a pattern.
        let ratings = Array(repeating: poorSleep, count: 3)
        let dates = [now.addingTimeInterval(-1 * 86_400),
                     now.addingTimeInterval(-2 * 86_400),
                     now.addingTimeInterval(-10 * 86_400)]
        #expect(ReadinessModulator.recentPattern(ratings: ratings, forDates: dates, now: now) == nil)
    }

    @Test func dominantPatternWins() throws {
        // Sleep poor 3 days, soreness poor 2 days → sleep is the surfaced pattern.
        let sleepPoor = ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .good)
        let sleepOnly = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good)
        let ratings = [sleepPoor, sleepPoor, sleepOnly]
        let dates = [now.addingTimeInterval(-1 * 86_400),
                     now.addingTimeInterval(-2 * 86_400),
                     now.addingTimeInterval(-3 * 86_400)]
        let pattern = try #require(ReadinessModulator.recentPattern(ratings: ratings, forDates: dates, now: now))
        #expect(pattern == .lowSleep(days: 3))   // sleep (3) beats soreness (2)
    }
}
