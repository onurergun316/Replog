//
//  RepSchemeTests.swift
//  ReplogTests
//
//  Verifies the program rep/intensity parser across the real shapes in the library:
//  counts, ranges, per-side, and time/hold/interval schemes, plus RPE extraction.
//

import Testing
import Foundation
@testable import Replog

struct RepSchemeTests {

    // MARK: - Counts & ranges

    @Test func plainCountParsesExactly() {
        #expect(RepScheme.parse(reps: "5") == RepTarget(reps: 5, isTimed: false, isPerSide: false))
        #expect(RepScheme.parse(reps: "12") == RepTarget(reps: 12, isTimed: false, isPerSide: false))
    }

    @Test func rangeTakesLowerBound() {
        #expect(RepScheme.parse(reps: "8-12").reps == 8)
        #expect(RepScheme.parse(reps: "10-15").reps == 10)
        #expect(RepScheme.parse(reps: "12-20").reps == 12)
    }

    @Test func perSideIsFlaggedAndCounted() {
        let side = RepScheme.parse(reps: "10/side")
        #expect(side.reps == 10)
        #expect(side.isPerSide)
        #expect(!side.isTimed)

        let leg = RepScheme.parse(reps: "10-12/leg")
        #expect(leg.reps == 10)
        #expect(leg.isPerSide)

        #expect(RepScheme.parse(reps: "12-15 each").isPerSide)
    }

    // MARK: - Time / hold / interval

    @Test func secondsAreParsedAsTimedSeconds() {
        let s = RepScheme.parse(reps: "30-60s")
        #expect(s.reps == 30)
        #expect(s.isTimed)

        #expect(RepScheme.parse(reps: "10s") == RepTarget(reps: 10, isTimed: true, isPerSide: false))
        #expect(RepScheme.parse(reps: "45 sec").reps == 45)
    }

    @Test func minutesConvertToSeconds() {
        #expect(RepScheme.parse(reps: "3 min") == RepTarget(reps: 180, isTimed: true, isPerSide: false))
        #expect(RepScheme.parse(reps: "10 min").reps == 600)   // clamped at 600 ceiling
    }

    @Test func perSideTimeCombines() {
        let t = RepScheme.parse(reps: "30s/side")
        #expect(t.reps == 30)
        #expect(t.isTimed)
        #expect(t.isPerSide)
    }

    // MARK: - Prose & edge cases

    @Test func unparseableProseFallsBackToDefaultReps() {
        #expect(RepScheme.parse(reps: "AMRAP") == RepTarget.fallback)
        #expect(RepScheme.parse(reps: "") == RepTarget.fallback)
        #expect(RepScheme.parse(reps: "to failure").reps == 10)
    }

    @Test func complexProseExtractsFirstNumber() {
        // "1 complex/side" → 1, per-side. "8 x (60s jog...)" → 8.
        let complex = RepScheme.parse(reps: "1 complex/side")
        #expect(complex.reps == 1)
        #expect(complex.isPerSide)
    }

    @Test func repsAreClampedToSaneBounds() {
        #expect(RepScheme.parse(reps: "999").reps == 50)   // rep ceiling
        #expect(RepScheme.parse(reps: "0").reps == 1)      // rep floor
    }

    // MARK: - RPE

    @Test func rpeParsesFromIntensityStrings() {
        #expect(RepScheme.parseRPE(intensity: "RPE 8") == 8)
        #expect(RepScheme.parseRPE(intensity: "rpe 7") == 7)
        #expect(RepScheme.parseRPE(intensity: "RPE 7-8") == 8)  // higher (ceiling) bound
        #expect(RepScheme.parseRPE(intensity: "@8") == 8)
    }

    @Test func rpeIsNilWhenAbsentOrOutOfRange() {
        #expect(RepScheme.parseRPE(intensity: "add 2.5kg per session") == nil)
        #expect(RepScheme.parseRPE(intensity: "70% 1RM") == nil)
        #expect(RepScheme.parseRPE(intensity: "RPE 15") == nil)   // out of 1...10
    }

    // MARK: - Building sets

    @Test func setsBuildsCountRepsAndRPEFromSlot() {
        let slot = ProgramSlot(pattern: .squat, sets: 3, reps: "8-12", intensity: "RPE 8")
        let sets = RepScheme.sets(for: slot, startingWeightKg: 40)
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.reps == 8 && $0.rpe == 8 && $0.weightKg == 40 })
    }

    @Test func setsUsesDefaultRPEWhenIntensityHasNone() {
        let slot = ProgramSlot(pattern: .hinge, sets: 1, reps: "5", intensity: "add 5kg per session")
        let sets = RepScheme.sets(for: slot, startingWeightKg: 60, defaultRPE: 9)
        #expect(sets.count == 1)
        #expect(sets.first?.rpe == 9)
        #expect(sets.first?.reps == 5)
    }

    @Test func setsClampsSlotSetCount() {
        let slot = ProgramSlot(pattern: .isolationArms, sets: 0, reps: "12", intensity: "RPE 8")
        #expect(RepScheme.sets(for: slot, startingWeightKg: 8).count == 1)  // at least one set
    }
}
