//
//  LoadCalibrator.swift
//  Replog
//
//  Turns a real logged set (weight × reps at a felt RPE) into the athlete's true working load
//  for a target rep/RPE scheme. This is what makes the conservative `StartingLoadEstimator`
//  seed safe: after the FIRST logged session, the actual weight-at-RPE — not the estimate —
//  drives the next recommendation, so an over- or under-seeded exercise self-corrects within a
//  session or two.
//
//  Math (uses the same Epley relationship as the rest of the app):
//   • A set of `w × reps` felt at `RPE` implies `10 − RPE` reps in reserve, i.e. it was really
//     `reps + (10 − RPE)` reps from failure. Its estimated 1RM is `w · (1 + repsToFailure/30)`.
//   • The load that hits the TARGET RPE at the target reps is `e1RM / (1 + targetRTF/30)`.
//  Over-seeded (felt harder than target → higher RPE) yields a lower next load; under-seeded a
//  higher one. Because the RPE scale saturates at 10, a wildly heavy seed converges over two
//  sessions rather than one — another reason the estimator deliberately errs low.
//

import Foundation

/// One logged set with the RPE the athlete actually felt.
nonisolated struct LoggedEffort: Equatable, Sendable {
    var weightKg: Double
    var reps: Int
    var rpe: Int
}

enum LoadCalibrator {

    /// Estimated 1RM implied by a logged set at its felt RPE (RIR-adjusted Epley).
    static func inferredE1RM(_ effort: LoggedEffort) -> Double {
        guard effort.weightKg > 0, effort.reps > 0 else { return 0 }
        let rir = Double(max(0, 10 - clampRPE(effort.rpe)))
        let repsToFailure = Double(effort.reps) + rir
        return effort.weightKg * (1 + repsToFailure / 30)
    }

    /// The working load (kg) that hits `targetRPE` at `targetReps` for a given 1RM.
    static func workingLoad(forE1RM e1rm: Double, targetReps: Int, targetRPE: Int,
                            stepKg: Double) -> Double {
        guard e1rm > 0, targetReps > 0 else { return 0 }
        let targetRTF = Double(targetReps + max(0, 10 - clampRPE(targetRPE)))
        let raw = e1rm / (1 + targetRTF / 30)
        return snap(raw, step: stepKg)
    }

    /// The next-session load calibrated from a logged set toward the target rep/RPE scheme.
    static func calibratedLoad(from effort: LoggedEffort, targetReps: Int, targetRPE: Int,
                               stepKg: Double = 2.5) -> Double {
        workingLoad(forE1RM: inferredE1RM(effort), targetReps: targetReps,
                    targetRPE: targetRPE, stepKg: stepKg)
    }

    // MARK: - Helpers

    private static func clampRPE(_ rpe: Int) -> Int { min(10, max(1, rpe)) }

    private static func snap(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return max(0, (value / step).rounded() * step)
    }
}
