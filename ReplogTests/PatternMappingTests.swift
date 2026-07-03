//
//  PatternMappingTests.swift
//  ReplogTests
//
//  Verifies the movement-pattern → catalog-facet mapping is total, and that per-pattern
//  candidate selection honors equipment, injuries, and the pattern's muscle/category intent.
//

import Testing
import Foundation
@testable import Replog

struct PatternMappingTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private let fullGym: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyOnly,
                                           .bands, .kettlebells, .medicineBall]

    // MARK: - Totality

    @Test func everyKnownPatternHasFacetsWithMuscleOrKeywordOrConditioning() {
        for pattern in MovementPattern.known {
            let f = PatternMapping.facets(for: pattern)
            // A pattern must give the resolver *something* to match on.
            let usable = !f.muscles.isEmpty || !f.nameKeywords.isEmpty || f.isConditioning
            #expect(usable, "\(pattern.rawValue) has no muscles/keywords/conditioning facet")
        }
    }

    @Test func unknownPatternFallsBackToGeneralStrength() {
        let f = PatternMapping.facets(for: .other("moonwalk"))
        #expect(f.category == .strength)
        #expect(!f.muscles.isEmpty)
    }

    @Test func everyKnownPatternYieldsCandidatesFromFullGymExceptSwim() {
        for pattern in MovementPattern.known {
            let cands = PatternMapping.candidates(for: pattern, allowedEquipment: fullGym, in: catalog)
            if pattern == .swim {
                #expect(cands.isEmpty, "swim has no catalog match and should yield nothing")
            } else {
                #expect(!cands.isEmpty, "\(pattern.rawValue) yielded no candidates from a full gym")
            }
        }
    }

    // MARK: - Strength patterns

    @Test func squatCandidatesTrainLegMusclesAsPrimary() {
        let cands = PatternMapping.candidates(for: .squat, allowedEquipment: fullGym, in: catalog)
        let legs: Set<Muscle> = [.quadriceps, .glutes, .hamstrings]
        #expect(cands.allSatisfy { !$0.primaryMuscles.filter(legs.contains).isEmpty })
        #expect(cands.allSatisfy { $0.category == .strength })
    }

    @Test func horizontalPushCandidatesTrainPushMuscles() {
        let cands = PatternMapping.candidates(for: .horizontalPush, allowedEquipment: fullGym, in: catalog)
        let push: Set<Muscle> = [.chest, .triceps, .shoulders]
        #expect(!cands.isEmpty)
        #expect(cands.allSatisfy { !$0.primaryMuscles.filter(push.contains).isEmpty })
    }

    @Test func candidatesNeverUseUnavailableEquipment() {
        let bodyweight: Set<Equipment> = [.bodyOnly]
        for pattern in MovementPattern.known {
            let cands = PatternMapping.candidates(for: pattern, allowedEquipment: bodyweight, in: catalog)
            #expect(cands.allSatisfy { bodyweight.contains($0.equipment ?? .bodyOnly) },
                    "\(pattern.rawValue) offered gear a bodyweight athlete lacks")
        }
    }

    @Test func injuryAvoidedMuscleNeverAppearsAsPrimaryMover() {
        // Knee avoids quads/hams/calves — squat candidates must not load those as primary.
        let avoid: Set<Muscle> = [.quadriceps, .hamstrings, .calves]
        let cands = PatternMapping.candidates(for: .squat, allowedEquipment: fullGym,
                                              avoidMuscles: avoid, in: catalog)
        #expect(cands.allSatisfy { $0.primaryMuscles.filter(avoid.contains).isEmpty })
    }

    @Test func slotMusclesRefineRanking() {
        // A hinge slot authored for glutes should rank a glute-primary movement ahead.
        let cands = PatternMapping.candidates(for: .hinge, slotMuscles: [.glutes],
                                              allowedEquipment: fullGym, in: catalog, limit: 5)
        #expect(!cands.isEmpty)
        #expect(cands.prefix(3).contains { $0.primaryMuscles.contains(.glutes) })
    }

    // MARK: - Conditioning / mobility patterns

    @Test func runCandidatesAreCardioMatchingKeywords() {
        let cands = PatternMapping.candidates(for: .run, allowedEquipment: fullGym, in: catalog)
        #expect(!cands.isEmpty)
        #expect(cands.allSatisfy { $0.category == .cardio })
        let keys = ["run", "jog", "sprint", "treadmill"]
        #expect(cands.allSatisfy { ex in keys.contains { ex.name.lowercased().contains($0) } })
    }

    @Test func stretchStaticCandidatesAreStretchingCategory() {
        let cands = PatternMapping.candidates(for: .stretchStatic, allowedEquipment: fullGym, in: catalog)
        #expect(!cands.isEmpty)
        #expect(cands.allSatisfy { $0.category == .stretching })
    }

    @Test func plyometricCandidatesArePlyometricCategory() {
        let cands = PatternMapping.candidates(for: .plyometric, allowedEquipment: fullGym, in: catalog)
        #expect(!cands.isEmpty)
        #expect(cands.allSatisfy { $0.category == .plyometrics })
    }
}
