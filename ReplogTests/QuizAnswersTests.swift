//
//  QuizAnswersTests.swift
//  ReplogTests
//
//  Derived values from the onboarding intake used by the AI prompt & coach report.
//

import Testing
import Foundation
@testable import Replog

struct QuizAnswersTests {

    @Test func fullNameTrimsAndJoins() {
        var a = QuizAnswers()
        a.firstName = "  Alex "
        a.lastName = " Carter "
        #expect(a.fullName == "Alex Carter")

        a.lastName = ""
        #expect(a.fullName == "Alex")

        a.firstName = "   "
        #expect(a.fullName == "")
    }

    @Test func bmiAndCategory() {
        var a = QuizAnswers()
        a.heightCm = 180
        a.bodyWeightKg = 81
        let bmi = a.bmi!
        #expect(abs(bmi - 25.0) < 0.1)
        #expect(a.bmiCategory == "overweight")

        a.bodyWeightKg = 65
        #expect(a.bmiCategory == "a healthy weight")

        a.bodyWeightKg = 50
        #expect(a.bmiCategory == "underweight")

        a.bodyWeightKg = 120
        #expect(a.bmiCategory == "in the obese range")
    }

    @Test func bmiNilWhenHeightUnset() {
        var a = QuizAnswers()
        a.heightCm = 0
        #expect(a.bmi == nil)
        #expect(a.bmiCategory == nil)
    }

    @Test func avoidedMusclesDeriveFromInjuries() {
        var a = QuizAnswers()
        a.injuries = [.knee, .shoulder]
        #expect(a.avoidedMuscles.contains(.quadriceps))
        #expect(a.avoidedMuscles.contains(.shoulders))
    }

    @Test func allowedEquipmentUsesSelectedTypesWhenSet() {
        var a = QuizAnswers()
        // Empty selection → falls back to the access level's default set.
        #expect(a.allowedEquipment == EquipmentAccess.fullGym.allowedEquipment)
        // Explicit selection restricts to exactly those types.
        a.equipmentTypes = [.dumbbell, .bodyOnly]
        #expect(a.allowedEquipment == [.dumbbell, .bodyOnly])
        #expect(a.equipmentDescription.contains("Dumbbell"))
        #expect(a.equipmentDescription.contains("Bodyweight"))
    }
}

@MainActor
struct EquipmentRestrictionTests {
    private let catalog = ExerciseCatalog(bundle: .main)

    @Test func candidatesOnlyUseSelectedEquipment() {
        var a = QuizAnswers()
        a.equipmentTypes = [.machine, .bodyOnly]
        let cands = PlanGenerator(catalog: catalog)
            .candidates(forMuscles: [.chest, .quadriceps], answers: a, limit: 14)
        #expect(!cands.isEmpty)
        for ex in cands {
            if let eq = ex.equipment { #expect(eq == .machine || eq == .bodyOnly) }
        }
    }

    @Test func deterministicPlanOnlyUsesSelectedEquipment() {
        var a = QuizAnswers()
        a.equipmentTypes = [.dumbbell, .bodyOnly]
        let plan = PlanGenerator(catalog: catalog).generate(a)
        for workout in plan.workouts {
            for item in workout.items {
                if let eq = catalog.exercise(id: item.exId)?.equipment {
                    #expect(eq == .dumbbell || eq == .bodyOnly)
                }
            }
        }
    }
}
