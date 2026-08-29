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

    @Test func fullNameUsesTrimmedFirstNameOnly() {
        var a = QuizAnswers()
        a.firstName = "  Alex "
        #expect(a.fullName == "Alex")

        a.firstName = "   "
        #expect(a.fullName == "")
    }

    @Test func genderDefaultsToMale() {
        #expect(QuizAnswers().gender == .male)
    }

    @Test func sportLabelUsesCustomTextForOther() {
        var a = QuizAnswers()
        #expect(a.sportLabel == "")            // no sport selected

        a.sport = .boxing
        #expect(a.sportLabel == "Boxing")

        a.sport = .other
        a.customSport = "  Fencing "
        #expect(a.sportLabel == "Fencing")     // trimmed free text

        a.sport = .running
        #expect(a.sportLabel == "Running")
    }

    @Test func otherSportHasNoFixedMuscleBias() {
        #expect(Sport.other.priorityMuscles.isEmpty)
        #expect(Sport.boxing.priorityMuscles.contains(.shoulders))
        #expect(Sport.volleyball.priorityMuscles.contains(.calves))
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

    @Test func machineOnlyNeverIncludesBodyweight() {
        // Regression: exercises with missing equipment (shown as "Bodyweight") used to leak
        // into a machine-only plan.
        var a = QuizAnswers()
        a.equipmentTypes = [.machine]
        let plan = PlanGenerator(catalog: catalog).generate(a)
        var machineCount = 0
        for workout in plan.workouts {
            for item in workout.items {
                #expect(catalog.exercise(id: item.exId)?.equipment == .machine)  // never nil/bodyweight/other
                machineCount += 1
            }
        }
        #expect(machineCount > 0)   // machine-only still produces a usable plan
    }

    @Test func machineOnlyCandidatesExcludeMissingEquipment() {
        var a = QuizAnswers()
        a.equipmentTypes = [.machine]
        let cands = PlanGenerator(catalog: catalog)
            .candidates(forMuscles: [.chest, .quadriceps, .abdominals], answers: a, limit: 20)
        for ex in cands { #expect(ex.equipment == .machine) }
    }

    // MARK: - Identity & copy for the pickers

    @Test func everyQuizEnumIsIdentifiedByItsRawValue() {
        // The onboarding pickers key their `ForEach` on these; a wrong id silently
        // collapses two options into one row.
        for value in Experience.allCases { #expect(value.id == value.rawValue) }
        for value in Gender.allCases { #expect(value.id == value.rawValue) }
        for value in Sport.allCases { #expect(value.id == value.rawValue) }
        for value in Injury.allCases { #expect(value.id == value.rawValue) }
        for value in EquipmentAccess.allCases { #expect(value.id == value.rawValue) }
        for value in Goal.allCases { #expect(value.id == value.rawValue) }
    }

    @Test func everyEquipmentAccessLevelIsNamedAndPermitsSomething() {
        for access in EquipmentAccess.allCases {
            #expect(!access.displayName.isEmpty)
            #expect(!access.allowedEquipment.isEmpty)
        }
        #expect(EquipmentAccess.home.displayName == "Home (dumbbells)")
        // Bodyweight-only is the narrowest and must never permit a barbell.
        #expect(!EquipmentAccess.bodyweight.allowedEquipment.contains(.barbell))
    }
}
