//
//  ProgressionEngine.swift
//  Replog
//
//  The deterministic core of the adaptive trainer: given one lift's logged history,
//  recommend what to do next session — add load, add reps, hold, or deload — with a
//  human-readable reason. Classic double progression: work up the rep range at a fixed
//  weight, add load when the top is reached, back off when the estimated 1RM regresses
//  or plateaus. All math lives here in code; the AI model never prescribes numbers.
//

import Foundation

/// What the trainer recommends for the next session of a lift.
enum ProgressionAction: String, Codable, CaseIterable, Sendable {
    case increaseLoad, increaseReps, hold, deload

    var displayName: String {
        switch self {
        case .increaseLoad: return "Add weight"
        case .increaseReps: return "Add a rep"
        case .hold:         return "Repeat"
        case .deload:       return "Deload"
        }
    }
}

/// A concrete next-session prescription for one lift, with the coach's reasoning.
struct ProgressionRecommendation: Equatable, Sendable {
    var exId: String
    var action: ProgressionAction
    /// Suggested working weight, stored in kg like every weight in the app.
    var suggestedWeightKg: Double
    var suggestedReps: Int
    /// One-sentence coach explanation, ready for the log card or a `CoachingLog`.
    var reason: String
}

enum ProgressionEngine {

    /// Deload target as a fraction of the last working weight (~10% off).
    static let deloadFactor = 0.9
    /// Consecutive e1RM *drops* that count as regressing (needs N+1 sessions).
    static let regressionDeltas = 2
    /// Consecutive sessions without an e1RM *improvement* that count as a plateau.
    static let plateauDeltas = 3

    /// The working rep range for double progression, per goal. Brackets the fixed
    /// prescription `PlanGenerator` writes (10 / 13 / 8 reps respectively).
    static func repRange(for goal: Goal) -> ClosedRange<Int> {
        switch goal {
        case .buildMuscle, .recomp: return 8...12
        case .loseWeight:           return 12...15
        case .sport:                return 6...10
        }
    }

    /// Convenience over the primary rule table: rep range from the goal, weight step
    /// and reason formatting from the user's display units.
    static func recommend(exId: String,
                          history: [HistoryEntry],
                          goal: Goal,
                          units: Units = .kg,
                          targetRPE: Int? = nil) -> ProgressionRecommendation? {
        recommend(exId: exId,
                  history: history,
                  repRange: repRange(for: goal),
                  weightStepKg: Formulas.weightStepKg(units: units),
                  units: units,
                  targetRPE: targetRPE)
    }

    /// The rule table. History may arrive in any order (sorted by date internally);
    /// pass only entries for `exId`. Returns nil when there is nothing to base a
    /// recommendation on. Rules, first match wins:
    /// 1. Bodyweight lift (top weight 0) → progress by reps only (hold when stalling).
    /// 2. Top of the rep range reached → increase load, rebuild from the bottom.
    /// 3. e1RM dropped `regressionDeltas` sessions in a row → deload ~10%.
    /// 4. No e1RM improvement across `plateauDeltas` sessions → deload ~10%.
    /// 5. Latest session dipped (single off day, not yet a trend) → hold.
    /// 6. Otherwise → add a rep (double progression).
    static func recommend(exId: String,
                          history: [HistoryEntry],
                          repRange: ClosedRange<Int>,
                          weightStepKg: Double = 2.5,
                          units: Units = .kg,
                          targetRPE: Int? = nil) -> ProgressionRecommendation? {
        let sorted = history.sorted { $0.date < $1.date }
        guard let last = sorted.last else { return nil }

        // Calibration (opt-in): after the FIRST logged session of a lift that was seeded with a
        // computed estimate, the real weight-at-RPE replaces the estimate. If the top set felt
        // meaningfully off the target RPE, retarget the load to the intended effort — a bad seed
        // self-corrects immediately instead of waiting for the double-progression rules.
        if let targetRPE, sorted.count == 1, last.topW > 0, abs(last.topRPE - targetRPE) >= 2 {
            let calibrated = LoadCalibrator.calibratedLoad(
                from: LoggedEffort(weightKg: last.topW, reps: last.topR, rpe: last.topRPE),
                targetReps: last.topR, targetRPE: targetRPE, stepKg: weightStepKg)
            if calibrated > 0, abs(calibrated - last.topW) >= weightStepKg {
                let reps = min(max(last.topR, repRange.lowerBound), repRange.upperBound)
                let heavier = calibrated > last.topW
                let w = { (kg: Double) in Formulas.formatWeight(kg: kg, units: units) }
                return ProgressionRecommendation(
                    exId: exId,
                    action: heavier ? .increaseLoad : .deload,
                    suggestedWeightKg: calibrated, suggestedReps: reps,
                    reason: "Calibrated from your first session — it felt like RPE \(last.topRPE), " +
                            "so \(w(calibrated)) better matches your target effort.")
            }
        }

        // Session-over-session e1RM deltas, oldest → newest.
        let series = sorted.map(\.e1rm)
        let deltas = zip(series.dropFirst(), series).map { $0 - $1 }
        let regressing = deltas.count >= regressionDeltas
            && deltas.suffix(regressionDeltas).allSatisfy { $0 < 0 }
        let plateaued = deltas.count >= plateauDeltas
            && deltas.suffix(plateauDeltas).allSatisfy { $0 <= 0 }

        let weight = { (kg: Double) in Formulas.formatWeight(kg: kg, units: units) }

        // Rule 1 — bodyweight: reps are the only lever, so the range top doesn't cap them.
        // e1RM is weight-based (always 0 here), so the stall signal comes from top reps.
        if last.topW == 0 {
            let repSeries = sorted.map(\.topR)
            let repDeltas = zip(repSeries.dropFirst(), repSeries).map { $0 - $1 }
            let repsRegressing = repDeltas.count >= regressionDeltas
                && repDeltas.suffix(regressionDeltas).allSatisfy { $0 < 0 }
            let repsPlateaued = repDeltas.count >= plateauDeltas
                && repDeltas.suffix(plateauDeltas).allSatisfy { $0 <= 0 }
            if repsRegressing || repsPlateaued {
                return ProgressionRecommendation(
                    exId: exId, action: .hold,
                    suggestedWeightKg: 0, suggestedReps: last.topR,
                    reason: "Progress has stalled — repeat \(last.topR) reps and focus on quality.")
            }
            return ProgressionRecommendation(
                exId: exId, action: .increaseReps,
                suggestedWeightKg: 0, suggestedReps: last.topR + 1,
                reason: "Add a rep — aim for \(last.topR + 1) next time.")
        }

        // Rule 2 — range top reached: add load, rebuild reps from the bottom.
        if last.topR >= repRange.upperBound {
            let next = last.topW + weightStepKg
            return ProgressionRecommendation(
                exId: exId, action: .increaseLoad,
                suggestedWeightKg: next, suggestedReps: repRange.lowerBound,
                reason: "You hit \(last.topR) reps at \(weight(last.topW)) — " +
                        "move up to \(weight(next)) and rebuild from \(repRange.lowerBound) reps.")
        }

        // Rules 3 & 4 — regression / plateau: take ~10% off and rebuild.
        if regressing || plateaued {
            let next = deloadWeight(fromKg: last.topW, stepKg: weightStepKg)
            let why = regressing
                ? "Est. 1RM has dropped \(regressionDeltas + 1) sessions in a row"
                : "No progress across your last \(plateauDeltas + 1) sessions"
            return ProgressionRecommendation(
                exId: exId, action: .deload,
                suggestedWeightKg: next, suggestedReps: repRange.lowerBound,
                reason: "\(why) — deload to \(weight(next)) and rebuild.")
        }

        // Rule 5 — a single down session is noise, not a trend: repeat and consolidate.
        if let lastDelta = deltas.last, lastDelta < 0 {
            let reps = min(max(last.topR, repRange.lowerBound), repRange.upperBound)
            return ProgressionRecommendation(
                exId: exId, action: .hold,
                suggestedWeightKg: last.topW, suggestedReps: reps,
                reason: "Last session dipped — repeat \(weight(last.topW)) × \(reps) and consolidate.")
        }

        // Rule 6 — double progression: same weight, one more rep (never below the range floor).
        let reps = max(min(last.topR + 1, repRange.upperBound), repRange.lowerBound)
        return ProgressionRecommendation(
            exId: exId, action: .increaseReps,
            suggestedWeightKg: last.topW, suggestedReps: reps,
            reason: "Progressing well — aim for \(weight(last.topW)) × \(reps).")
    }

    /// ~10% off the working weight, snapped to the stepper increment, always strictly
    /// below the current weight (floored at 0).
    static func deloadWeight(fromKg kg: Double, stepKg: Double) -> Double {
        guard kg > 0 else { return 0 }
        let target = kg * deloadFactor
        guard stepKg > 0 else { return target }
        var snapped = (target / stepKg).rounded() * stepKg
        if snapped >= kg { snapped -= stepKg }
        return max(0, snapped)
    }
}
