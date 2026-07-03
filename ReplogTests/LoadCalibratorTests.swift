//
//  LoadCalibratorTests.swift
//  ReplogTests
//
//  The RPE-aware load calibrator: inferred 1RM math, direction of correction, and convergence
//  of an over- and under-seeded exercise toward its true working load within 1–2 sessions.
//

import Testing
import Foundation
@testable import Replog

struct LoadCalibratorTests {

    // MARK: - Core math

    @Test func inferredE1RMUsesRIRAdjustedEpley() {
        // 60 kg × 8 @ RPE 8 → 2 reps in reserve → 10 reps from failure → e1RM = 60 × (1 + 10/30).
        #expect(LoadCalibrator.inferredE1RM(LoggedEffort(weightKg: 60, reps: 8, rpe: 8)) == 80)
        // At RPE 10 (0 RIR) it's the plain Epley of the set.
        let plainEpley: Double = 100 * (1 + 5.0 / 30)
        #expect(LoadCalibrator.inferredE1RM(LoggedEffort(weightKg: 100, reps: 5, rpe: 10)) == plainEpley)
    }

    @Test func workingLoadInvertsCleanlyAtTarget() {
        #expect(LoadCalibrator.workingLoad(forE1RM: 80, targetReps: 8, targetRPE: 8, stepKg: 2.5) == 60)
    }

    @Test func atTargetRPEThereIsNoChange() {
        #expect(LoadCalibrator.calibratedLoad(from: LoggedEffort(weightKg: 60, reps: 8, rpe: 8),
                                              targetReps: 8, targetRPE: 8, stepKg: 2.5) == 60)
    }

    @Test func overSeededSetCalibratesDown() {
        // Logged too hard (RPE 10 when target is 8) → next load is lighter.
        let next = LoadCalibrator.calibratedLoad(from: LoggedEffort(weightKg: 100, reps: 8, rpe: 10),
                                                 targetReps: 8, targetRPE: 8, stepKg: 2.5)
        #expect(next < 100)
    }

    @Test func underSeededSetCalibratesUp() {
        // Logged too easy (RPE 5 when target is 8) → next load is heavier.
        let next = LoadCalibrator.calibratedLoad(from: LoggedEffort(weightKg: 40, reps: 8, rpe: 5),
                                                 targetReps: 8, targetRPE: 8, stepKg: 2.5)
        #expect(next > 40)
    }

    @Test func bodyweightAndZeroInputsAreSafe() {
        #expect(LoadCalibrator.inferredE1RM(LoggedEffort(weightKg: 0, reps: 8, rpe: 8)) == 0)
        #expect(LoadCalibrator.calibratedLoad(from: LoggedEffort(weightKg: 0, reps: 8, rpe: 8),
                                              targetReps: 8, targetRPE: 8) == 0)
    }

    // MARK: - Convergence (the safety net for a conservative seed)

    /// The RPE an athlete of a given true strength would feel lifting `weight` for `reps`.
    private func feltRPE(weight: Double, trueE1RM: Double, reps: Int) -> Int {
        let repsToFailure = (trueE1RM / weight - 1) * 30
        let rpe = 10 - (repsToFailure - Double(reps))
        return min(10, max(1, Int(rpe.rounded())))
    }

    /// Simulates `iterations` of log → calibrate, starting from `seed`, for an athlete whose
    /// true load at (reps, rpe) is `trueWeight`.
    private func converge(seed: Double, trueWeight: Double, reps: Int, rpe: Int,
                          step: Double, iterations: Int) -> Double {
        let trueE1RM = trueWeight * (1 + Double(reps + (10 - rpe)) / 30)
        var w = seed
        for _ in 0..<iterations {
            let felt = feltRPE(weight: w, trueE1RM: trueE1RM, reps: reps)
            w = LoadCalibrator.calibratedLoad(from: LoggedEffort(weightKg: w, reps: reps, rpe: felt),
                                              targetReps: reps, targetRPE: rpe, stepKg: step)
        }
        return w
    }

    @Test func underSeededExerciseConvergesWithinTwoSessions() {
        let result = converge(seed: 45, trueWeight: 60, reps: 8, rpe: 8, step: 2.5, iterations: 2)
        #expect(abs(result - 60) <= 2.5)
    }

    @Test func overSeededExerciseConvergesWithinTwoSessions() {
        let result = converge(seed: 68, trueWeight: 60, reps: 8, rpe: 8, step: 2.5, iterations: 2)
        #expect(abs(result - 60) <= 2.5)
    }

    @Test func eachCalibrationStepMovesTowardTheTrueLoad() {
        // Under-seeded: the first calibration is already strictly closer to the true load.
        let step1 = converge(seed: 45, trueWeight: 60, reps: 8, rpe: 8, step: 2.5, iterations: 1)
        #expect(abs(step1 - 60) < abs(45 - 60))
    }
}
