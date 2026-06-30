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
}
