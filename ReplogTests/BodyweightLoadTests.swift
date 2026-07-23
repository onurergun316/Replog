//
//  BodyweightLoadTests.swift
//  ReplogTests
//
//  The %BW factor table: every bodyweight movement in the shipped catalog must resolve
//  to a defensible fraction, nothing that isn't bodyweight-loaded may resolve at all,
//  and the keyword ordering must survive the names that overlap two families.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct BodyweightLoadTests {

    private let catalog = ExerciseCatalog.shared

    private func exercise(_ id: String) throws -> Exercise {
        try #require(catalog.exercise(id: id), "missing catalog entry \(id)")
    }

    private func factor(_ id: String) throws -> Double {
        try #require(BodyweightLoad.factor(for: exercise(id)))
    }

    // MARK: - Coverage over the real catalog

    @Test func everyBodyweightMovementResolvesToAPlausibleFraction() throws {
        let loaded = catalog.all.filter(BodyweightLoad.isBodyweightLoaded)
        #expect(!loaded.isEmpty)

        for ex in loaded {
            let f = try #require(BodyweightLoad.factor(for: ex), "no factor for \(ex.id)")
            // Below 5% isn't a training stimulus worth recording; above 100% would mean
            // the movement loads more than the athlete weighs, which none of these do.
            #expect(f >= 0.05 && f <= 1.0, "implausible factor \(f) for \(ex.name)")
        }
    }

    @Test func nothingOutsideTheBodyweightFamilyResolves() throws {
        for ex in catalog.all where !BodyweightLoad.isBodyweightLoaded(ex) {
            #expect(BodyweightLoad.factor(for: ex) == nil, "\(ex.name) should not resolve")
        }
    }

    @Test func stretchingAndCardioEarnNoCredit() throws {
        // Equipment-free, but not lifting: crediting these would inflate every total in
        // the app, and they are 85 of the catalog's 188 equipment-free entries.
        let excluded = catalog.all.filter {
            ($0.equipment ?? .bodyOnly) == .bodyOnly && ($0.category == .stretching || $0.category == .cardio)
        }
        #expect(!excluded.isEmpty)
        #expect(excluded.allSatisfy { BodyweightLoad.factor(for: $0) == nil })
    }

    @Test func barbellWorkIsNotBodyweightLoaded() throws {
        let bench = try exercise("Barbell_Bench_Press_-_Medium_Grip")
        #expect(!BodyweightLoad.isBodyweightLoaded(bench))
        #expect(BodyweightLoad.factor(for: bench) == nil)
    }

    // MARK: - Timed holds

    @Test func holdsAreExactlyTheStaticBodyweightMovements() throws {
        let holds = catalog.all.filter(BodyweightLoad.isTimedHold)
        #expect(Set(holds.map(\.id)) == [
            "Plank", "Side_Bridge", "Isometric_Chest_Squeezes",
            "Isometric_Neck_Exercise_-_Front_And_Back",
            "Isometric_Neck_Exercise_-_Sides",
        ])
    }

    @Test func aPartnerResistedRepExerciseIsNotAHold() throws {
        // The catalog marks Prone Manual Hamstring `static` (no concentric direction),
        // but it is performed for reps. Treating it as a hold would label its reps as
        // seconds in the live log and credit a third of its real tonnage.
        let prone = try exercise("Prone_Manual_Hamstring")
        #expect(prone.force == .static)
        #expect(!BodyweightLoad.isTimedHold(prone))
        #expect(BodyweightLoad.repEquivalents(reps: 12, exercise: prone) == 12)
    }

    @Test func aHoldsSecondsBecomeRepEquivalents() throws {
        let plank = try exercise("Plank")
        // 30 s of plank is 10 rep-equivalents, not 30 reps.
        #expect(BodyweightLoad.repEquivalents(reps: 30, exercise: plank) == 10)

        let pushup = try exercise("Pushups")
        #expect(BodyweightLoad.repEquivalents(reps: 30, exercise: pushup) == 30)
        #expect(BodyweightLoad.repEquivalents(reps: 12, exercise: nil) == 12)
    }

    @Test func neckIsometricsAreCreditedAtHeadMass() throws {
        #expect(try factor("Isometric_Neck_Exercise_-_Sides") == 0.08)
    }

    // MARK: - Keyword ordering (the names that belong to two families)

    @Test func benchDipIsNotCreditedAsAFullDip() throws {
        // Feet on the floor carry roughly 40% of the load away from the arms.
        #expect(try factor("Bench_Dips") == 0.60)
        #expect(try factor("Dips_-_Triceps_Version") == 0.95)
    }

    @Test func pushUpVariantsSeparateByHandHeight() throws {
        #expect(try factor("Pushups") == 0.64)
        #expect(try factor("Incline_Push-Up") == 0.45)         // hands elevated: less load
        #expect(try factor("Decline_Push-Up") == 0.70)         // feet elevated: more load
        #expect(try factor("Push-Ups_With_Feet_Elevated") == 0.70)
        #expect(try factor("Handstand_Push-Ups") == 0.90)
        // "decline" must not be read as "incline".
        #expect(try factor("Decline_Push-Up") != factor("Incline_Push-Up"))
    }

    @Test func reverseCrunchIsALegRaiseNotACrunch() throws {
        // It lifts the legs, not the shoulders — a different fraction of the body.
        #expect(try factor("Reverse_Crunch") == 0.30)
        #expect(try factor("Decline_Reverse_Crunch") == 0.30)
        #expect(try factor("Crunches") == 0.20)
    }

    @Test func aJumpSquatIsCreditedAsAJump() throws {
        // The whole body leaves the floor, which is more than a bodyweight squat moves.
        #expect(try factor("Freehand_Jump_Squat") == 1.00)
        #expect(try factor("Bodyweight_Squat") == 0.75)
    }

    @Test func stepUpWithKneeRaiseIsAStepUp() throws {
        // Contains "knee raise", but the movement is loaded like a step-up.
        #expect(try factor("Step-up_with_Knee_Raise") == 0.75)
        #expect(try factor("Hanging_Leg_Raise") == 0.30)
    }

    @Test func aLegPullInIsNotAPullUp() throws {
        #expect(try factor("Leg_Pull-In") == 0.30)
        #expect(try factor("Pullups") == 0.95)
    }

    @Test func hangingCrunchIsCreditedAsSuspension() throws {
        // Named like a crunch, performed hanging from a bar.
        #expect(try factor("Gorilla_Chin_Crunch") == 0.95)
    }

    // MARK: - Fallback

    @Test func unnamedMovementsFallBackByPrimaryMuscle() throws {
        // "Body-Up" matches no keyword; it is a triceps push, so it lands on the push share.
        #expect(try factor("Body-Up") == 0.64)
        // "Bottoms Up" matches no keyword; an abdominal move lands on the trunk share.
        #expect(try factor("Bottoms_Up") == 0.30)
    }

    @Test func unnamedSprintDrillsGetTheConservativeDefault() throws {
        // A wall drill's "rep" is a stride, not a lift. Reading its primary mover
        // (hamstrings) would credit it like a bodyweight squat, which is far too generous.
        #expect(try factor("Linear_Acceleration_Wall_Drill") == 0.50)
        #expect(try factor("Kneeling_Arm_Drill") == 0.50)
    }

    // MARK: - Effective load

    @Test func bodyweightMovementsAreWorthTheirShareOfTheAthlete() throws {
        let pullup = try exercise("Pullups")
        // An 80 kg athlete doing bodyweight pull-ups: 0.95 x 80.
        #expect(BodyweightLoad.effectiveKg(addedKg: 0, exercise: pullup, bodyweightKg: 80) == 76)
    }

    @Test func addedWeightLayersOnTopOfBodyweight() throws {
        let pullup = try exercise("Pullups")
        // A 10 kg dip belt on the same athlete.
        #expect(BodyweightLoad.effectiveKg(addedKg: 10, exercise: pullup, bodyweightKg: 80) == 86)
    }

    @Test func externalLoadIsUnchanged() throws {
        let bench = try exercise("Barbell_Bench_Press_-_Medium_Grip")
        #expect(BodyweightLoad.effectiveKg(addedKg: 100, exercise: bench, bodyweightKg: 80) == 100)
    }

    @Test func missingBodyweightOrExerciseFallsBackToTheStoredWeight() throws {
        let pullup = try exercise("Pullups")
        // Never invent a number: with no bodyweight on file, report what was logged.
        #expect(BodyweightLoad.effectiveKg(addedKg: 10, exercise: pullup, bodyweightKg: nil) == 10)
        #expect(BodyweightLoad.effectiveKg(addedKg: 10, exercise: pullup, bodyweightKg: 0) == 10)
        #expect(BodyweightLoad.effectiveKg(addedKg: 60, exercise: nil, bodyweightKg: 80) == 60)
    }
}
