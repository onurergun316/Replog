//
//  StartingLoadEstimatorTests.swift
//  ReplogTests
//
//  The science-based per-user starting-load model: sex/experience scaling, the upper vs lower
//  sex gap, equipment floors, and bodyweight movements. Absolute-ceiling assertions guard
//  against the old hardcoded-weight bug (no 25 kg female-beginner curls, ever).
//

import Testing
import Foundation
@testable import Replog

struct StartingLoadEstimatorTests {

    private let femaleBeginner = LoadUser(sex: .female, experience: .beginner, bodyweightKg: 62)
    private let maleAdvanced   = LoadUser(sex: .male, experience: .advanced, bodyweightKg: 85)
    private let maleBeginner   = LoadUser(sex: .male, experience: .beginner, bodyweightKg: 80)

    private func req(_ pattern: StrengthPattern, _ loading: LoadingType,
                     reps: Int = 8, rpe: Int = 8) -> LoadRequest {
        LoadRequest(pattern: pattern, loading: loading, targetReps: reps, targetRPE: rpe)
    }

    // MARK: - Female beginner vs male advanced, sane bands

    @Test func femaleBeginnerLoadsAreDramaticallyLowerThanMaleAdvanced() {
        let curl = req(.isolation, .dumbbellPerHand, reps: 12)
        let fb = StartingLoadEstimator.estimate(curl, user: femaleBeginner).kg
        let ma = StartingLoadEstimator.estimate(curl, user: maleAdvanced).kg
        #expect(fb < ma)
        #expect(fb < ma / 2)   // dramatically lower, not a small delta
    }

    @Test func femaleBeginnerHammerCurlIsWellUnderEightKgPerHand() {
        let curl = req(.isolation, .dumbbellPerHand, reps: 12)
        let kg = StartingLoadEstimator.estimate(curl, user: femaleBeginner).kg
        #expect(kg > 0)
        #expect(kg < 8)   // no absurd dumbbell curls
    }

    @Test func femaleBeginnerBarbellCurlNeverExceedsAnEmptyBar() {
        let curl = req(.isolation, .barbell, reps: 12)
        let kg = StartingLoadEstimator.estimate(curl, user: femaleBeginner).kg
        // A light barbell curl for a female beginner floors at the empty bar — never 25 kg.
        #expect(kg <= StartingLoadEstimator.emptyBarKg)
    }

    // MARK: - Upper vs lower sex gap (~0.55 vs ~0.68)

    @Test func femaleMaleRatioIsSmallerForUpperBodyThanLower() {
        // Use the unrounded value so equipment floors/rounding don't mask the coefficients.
        func ratio(_ pattern: StrengthPattern) -> Double {
            let f = StartingLoadEstimator.unroundedKg(req(pattern, .barbell), user:
                LoadUser(sex: .female, experience: .beginner, bodyweightKg: 70))
            let m = StartingLoadEstimator.unroundedKg(req(pattern, .barbell), user:
                LoadUser(sex: .male, experience: .beginner, bodyweightKg: 70))
            return f / m
        }
        let upper = ratio(.upperPush)
        let lower = ratio(.lowerCompound)
        #expect(upper < lower)
        #expect(abs(upper - StartingLoadEstimator.femaleUpperCoeff) < 0.001)
        #expect(abs(lower - StartingLoadEstimator.femaleLowerCoeff) < 0.001)
    }

    @Test func sexCoefficientsEncodeTheFinding() {
        #expect(StartingLoadEstimator.femaleUpperCoeff < StartingLoadEstimator.femaleLowerCoeff)
        #expect(StartingLoadEstimator.femaleUpperCoeff < 1.0)
        // Unspecified sex is a conservative midpoint between the female coeff and male (1.0).
        #expect(StartingLoadEstimator.unspecifiedUpperCoeff > StartingLoadEstimator.femaleUpperCoeff)
        #expect(StartingLoadEstimator.unspecifiedUpperCoeff < 1.0)
    }

    // MARK: - Equipment floors

    @Test func barbellLoadsNeverDropBelowAnEmptyBar() {
        let users = [femaleBeginner, maleBeginner, maleAdvanced,
                     LoadUser(sex: .female, experience: .beginner, bodyweightKg: 48)]
        let patterns: [StrengthPattern] = [.lowerCompound, .upperPush, .upperPull, .isolation]
        for user in users {
            for pattern in patterns {
                let kg = StartingLoadEstimator.estimate(req(pattern, .barbell), user: user).kg
                #expect(kg >= StartingLoadEstimator.emptyBarKg, "\(pattern) barbell below empty bar")
            }
        }
    }

    @Test func dumbbellAndMachineHaveSaneNonZeroFloors() {
        let dumbbell = StartingLoadEstimator.estimate(req(.isolation, .dumbbellPerHand),
                                                      user: femaleBeginner).kg
        let machine = StartingLoadEstimator.estimate(req(.upperPush, .machine), user: femaleBeginner).kg
        #expect(dumbbell >= 1)
        #expect(machine >= 5)
    }

    // MARK: - Experience monotonicity (same everything else)

    @Test func advancedSeedsHeavierThanIntermediateThanBeginner() {
        let squat = req(.lowerCompound, .barbell, reps: 5)
        func kg(_ e: Experience) -> Double {
            StartingLoadEstimator.estimate(squat, user:
                LoadUser(sex: .male, experience: e, bodyweightKg: 85)).kg
        }
        #expect(kg(.advanced) > kg(.intermediate))
        #expect(kg(.intermediate) > kg(.beginner))
    }

    @Test func sexScalingDoesNotChangeExperienceOrdering() {
        // Ordering by experience holds for women too (sex scales the estimate, not the response).
        let press = req(.upperPush, .machine, reps: 8)
        func kg(_ e: Experience) -> Double {
            StartingLoadEstimator.estimate(press, user:
                LoadUser(sex: .female, experience: e, bodyweightKg: 62)).kg
        }
        #expect(kg(.advanced) >= kg(.intermediate))
        #expect(kg(.intermediate) >= kg(.beginner))
    }

    // MARK: - Bodyweight movements

    @Test func bodyweightMovementsEmitNoExternalLoad() {
        let est = StartingLoadEstimator.estimate(req(.upperPush, .bodyweight), user: maleAdvanced)
        #expect(est.kg == 0)
        #expect(est.isBodyweight)
        #expect(!est.note.isEmpty)
    }

    // MARK: - Exercise mapping (against the real catalog)

    @Test func catalogMappingClassifiesLoadingAndBodyweight() throws {
        let catalog = ExerciseCatalog(bundle: .main)
        let bodyOnly = try #require(catalog.all.first { $0.equipment == .bodyOnly })
        #expect(StartingLoadEstimator.loading(for: bodyOnly) == .bodyweight)
        #expect(StartingLoadEstimator.estimate(for: bodyOnly, targetReps: 10, targetRPE: 8,
                                               user: maleBeginner).kg == 0)

        let barbell = try #require(catalog.all.first { $0.equipment == .barbell })
        #expect(StartingLoadEstimator.loading(for: barbell) == .barbell)
    }

    @Test func lowerBodyBarbellMapsToLowerCompound() throws {
        let catalog = ExerciseCatalog(bundle: .main)
        let squat = try #require(catalog.all.first {
            $0.equipment == .barbell && $0.mechanic == .compound && $0.primaryMuscles.contains(.quadriceps)
        })
        #expect(StartingLoadEstimator.pattern(for: squat) == .lowerCompound)
    }

    @Test func noteExplainsTheSourceForTheCoach() {
        let note = StartingLoadEstimator.estimate(req(.upperPush, .barbell), user: femaleBeginner).note
        #expect(note.contains("female"))
        #expect(note.contains("beginner"))
        #expect(note.contains("calibrate"))
    }
}
