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

// MARK: - Distances are distances

@MainActor
struct RepSchemeDistanceTests {

    @Test func aBareMetreIsNotAMinute() {
        // "20m" is a twenty-metre farmer's carry. Read as minutes it became 1200 seconds,
        // clamped to the 600s ceiling — a ten-minute carry set, written into real plans.
        // 32 slots across the library parsed this way.
        let carry = RepScheme.parse(reps: "20m", pattern: .carry)
        #expect(carry.isTimed)
        #expect(carry.reps == 25)          // 20 m at ~0.8 m/s
        #expect(carry.reps < 600)
    }

    @Test func minutesStillHaveToSayMinutes() {
        #expect(RepScheme.parse(reps: "3 min").reps == 180)
        #expect(RepScheme.parse(reps: "20 min hard").reps == 600)   // clamped at the 10-minute ceiling
        #expect(RepScheme.parse(reps: "45s").reps == 45)
        #expect(RepScheme.parse(reps: "30-60s").reps == 30)
    }

    @Test func aDistanceCostsWhatTheMovementCosts() {
        // The same 200 metres is five minutes of swimming and a minute of running.
        let swim = RepScheme.parse(reps: "200m", pattern: .swim)
        let run = RepScheme.parse(reps: "200m", pattern: .run)
        #expect(swim.reps == 300)
        #expect(run.reps == 60)
        #expect(swim.reps > run.reps)
    }

    @Test func aSprintIsNotATenMinuteEffort() {
        let sprint = RepScheme.parse(reps: "20m from standing", pattern: .run)
        #expect(sprint.isTimed)
        #expect(sprint.reps == 6)
    }

    @Test func aRepSchemeWithADistanceAlternativeStaysARepScheme() {
        // "10-12 or 30m": the unit belongs to the second alternative, not the first number.
        let target = RepScheme.parse(reps: "10-12 or 30m", pattern: .carry)
        #expect(!target.isTimed)
        #expect(target.reps == 10)
    }

    @Test func aUnitMentionedLaterInTheStringDoesNotClaimTheFirstNumber() {
        // "6 x 30m shuttle, 20s between reps, 3 min between sets" was a SIX-MINUTE set,
        // because the string mentions minutes somewhere.
        let shuttle = RepScheme.parse(reps: "6 x 30m shuttle, 20s between reps, 3 min between sets",
                                      pattern: .run)
        #expect(!shuttle.isTimed)
        #expect(shuttle.reps == 6)
    }

    @Test func aRangeStillCarriesItsUnitAtTheEnd() {
        #expect(RepScheme.parse(reps: "30-60s").reps == 30)
        #expect(RepScheme.parse(reps: "30-60s").isTimed)
        #expect(RepScheme.parse(reps: "8-12 min").reps == 480)
        #expect(RepScheme.parse(reps: "8-12").reps == 8)
        #expect(!RepScheme.parse(reps: "8-12").isTimed)
    }

    @Test func noDistanceSlotBecomesATenMinuteSet() {
        // Library-wide guard on the defect's signature: a distance must never land ON the
        // 600-second ceiling, which is what told us it had been read as minutes and clamped.
        // Being long is not the bug — a 300 m continuous swim really is about 7 minutes.
        // Genuine long efforts written in minutes ("10 min steady") are untouched.
        let programs = ProgramCatalog(bundle: .main)
        for program in programs.all {
            for day in program.days {
                for slot in day.slots where !slot.reps.lowercased().contains("min") {
                    let target = RepScheme.parse(reps: slot.reps, pattern: slot.pattern)
                    if target.isTimed {
                        #expect(target.reps < 600,
                                "\(program.id) \"\(slot.reps)\" -> \(target.reps)s (clamped)")
                    }
                }
            }
        }
    }
}
