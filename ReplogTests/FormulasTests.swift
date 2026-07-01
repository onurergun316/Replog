//
//  FormulasTests.swift
//  ReplogTests
//

import Testing
import Foundation
@testable import Replog

struct FormulasTests {

    @Test func epleyE1RM() {
        // Epley has no special case at 1 rep: 100 * (1 + 1/30) = 103.33…
        #expect(abs(Formulas.e1rm(kg: 100, reps: 1) - 103.333) < 0.01)
        // 100 * (1 + 10/30) = 133.33…
        #expect(abs(Formulas.e1rm(kg: 100, reps: 10) - 133.333) < 0.01)
        // 0 reps guards to 0.
        #expect(Formulas.e1rm(kg: 100, reps: 0) == 0)
    }

    @Test func e1rmRounded() {
        #expect(Formulas.e1rmRounded(kg: 90, reps: 8) == 114) // 90*(1+8/30)=114.0
        #expect(Formulas.e1rmRounded(kg: 60, reps: 12) == 84) // 60*1.4=84
    }

    @Test func kgToLbRoundsToNearestFive() {
        // 100kg = 220.46lb -> nearest 5 = 220.
        #expect(Formulas.kgToLb(100) == 220)
        // 60kg = 132.3lb -> nearest 5 = 130.
        #expect(Formulas.kgToLb(60) == 130)
        // 2.5kg = 5.51lb -> nearest 5 = 5.
        #expect(Formulas.kgToLb(2.5) == 5)
    }

    @Test func weightStepIncrements() {
        #expect(Formulas.weightStepKg(units: .kg) == 2.5)
        // +5 lb in kg ≈ 2.2679
        #expect(abs(Formulas.weightStepKg(units: .lb) - 2.2679) < 0.001)
    }

    @Test func displayWeightConversion() {
        #expect(Formulas.displayWeight(kg: 100, units: .kg) == 100)
        #expect(Formulas.displayWeight(kg: 100, units: .lb) == 220)
    }

    @Test func formatWeightDropsTrailingZero() {
        #expect(Formulas.formatWeight(kg: 100, units: .kg) == "100kg")
        #expect(Formulas.formatWeight(kg: 100, units: .lb) == "220lb")
        #expect(Formulas.formatWeight(kg: 2.5, units: .kg) == "2.5kg")
        #expect(Formulas.formatWeight(kg: 60, units: .kg, includeUnit: false) == "60")
    }

    @Test func parseWeightKgAcceptsDecimalsAndConvertsUnits() {
        #expect(Formulas.parseWeightKg("60", units: .kg) == 60)
        #expect(Formulas.parseWeightKg("62,5", units: .kg) == 62.5)   // comma decimal
        #expect(Formulas.parseWeightKg("  70 ", units: .kg) == 70)    // trimmed
        // In lb, the typed value converts back to kg.
        #expect(abs((Formulas.parseWeightKg("220", units: .lb) ?? 0) - 99.79) < 0.1)
    }

    @Test func parseWeightKgClampsAndRejectsGarbage() {
        #expect(Formulas.parseWeightKg("-10", units: .kg) == 0)       // clamps to ≥ 0
        #expect(Formulas.parseWeightKg("abc", units: .kg) == nil)
        #expect(Formulas.parseWeightKg("", units: .kg) == nil)
    }

    @Test func parseRepsClampsToPositiveInteger() {
        #expect(Formulas.parseReps("8") == 8)
        #expect(Formulas.parseReps("0") == 1)      // clamps to ≥ 1
        #expect(Formulas.parseReps("12reps") == 12) // strips non-digits
        #expect(Formulas.parseReps("x") == nil)
    }
}
