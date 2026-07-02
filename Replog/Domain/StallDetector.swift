//
//  StallDetector.swift
//  Replog
//
//  Cross-session stall detection (B3): the trainer's long-horizon eye. Where
//  `ProgressionEngine` prescribes the *next session*, `StallDetector` watches the
//  trailing trend of a lift, decides whether it has genuinely stalled, and — once
//  per stall — writes the recommendation into the coaching memory (`CoachingLog`):
//  deload first; if the history shows a deload was already tried and the lift is
//  stuck again, recommend swapping to a similar movement instead.
//

import Foundation
import SwiftData

/// The shape of a detected stall.
enum StallTrend: String, Codable, Sendable {
    /// Estimated 1RM (or top reps, for bodyweight lifts) is falling.
    case regression
    /// No improvement across recent sessions.
    case plateau
}

/// What the trainer recommends in response to a stall.
enum StallResponse: String, Codable, Sendable {
    /// Back off ~10% and rebuild — the first remedy for a weighted lift.
    case deload
    /// A deload was already tried (or there is no load to shed) — change the stimulus.
    case swapExercise
}

/// A detected stall on one lift, ready to be recorded to the coaching memory.
struct StallDetection: Equatable, Sendable {
    var exId: String
    var trend: StallTrend
    var response: StallResponse
    /// Sessions covered by the trailing non-improving run (≥ the trigger threshold).
    var sessionsStalled: Int
    /// Date of the first session in the stalled run — used to record each stall once.
    var stallStartDate: Date
    var lastTopWeightKg: Double
    var lastTopReps: Int
    var lastE1RM: Int
}

enum StallDetector {

    /// A session-over-session top-weight drop of at least this fraction reads as a
    /// deliberate back-off (a deload), not a failed attempt at the same load.
    static let backoffFraction = 0.05
    /// How many recent session-over-session steps to scan for an already-tried deload
    /// when deciding to escalate from "deload" to "swap the exercise".
    static let swapLookbackDeltas = 8

    // MARK: - Detection (pure)

    /// Detects a stall in one lift's history (entries for `exId` only, any order).
    /// Returns nil while the lift is progressing, has too little history, or the
    /// latest session is itself a back-off (a rebuild in progress is not a stall).
    static func detect(exId: String, history: [HistoryEntry]) -> StallDetection? {
        let sorted = history.sorted { $0.date < $1.date }
        guard let last = sorted.last,
              sorted.count > ProgressionEngine.regressionDeltas else { return nil }

        // Bodyweight lifts trend on top reps — stored e1RM is weight-based, always 0.
        if last.topW == 0 {
            guard let run = stallRun(in: sorted.map { Double($0.topR) }) else { return nil }
            return StallDetection(
                exId: exId, trend: run.trend,
                // There is no load to shed, so the only remedy is a different stimulus.
                response: .swapExercise,
                sessionsStalled: run.length + 1,
                stallStartDate: sorted[sorted.count - 1 - run.length].date,
                lastTopWeightKg: 0, lastTopReps: last.topR, lastE1RM: last.e1rm)
        }

        let weights = sorted.map(\.topW)
        // The latest session backed the weight off → the user is rebuilding, not stuck.
        if isBackoff(from: weights[weights.count - 2], to: weights[weights.count - 1]) {
            return nil
        }

        guard let run = stallRun(in: sorted.map { Double($0.e1rm) }) else { return nil }

        // Escalate when a back-off already happened recently *before* the current run
        // (the run's own drops are the regression, not a tried remedy): the deload
        // didn't fix it, so recommend changing the exercise.
        let deltaCount = sorted.count - 1
        let newestEligible = deltaCount - run.length
        let oldestEligible = max(1, deltaCount - swapLookbackDeltas + 1)
        let deloadTried = newestEligible >= oldestEligible
            && (oldestEligible...newestEligible).contains { isBackoff(from: weights[$0 - 1], to: weights[$0]) }

        return StallDetection(
            exId: exId, trend: run.trend,
            response: deloadTried ? .swapExercise : .deload,
            sessionsStalled: run.length + 1,
            stallStartDate: sorted[sorted.count - 1 - run.length].date,
            lastTopWeightKg: last.topW, lastTopReps: last.topR, lastE1RM: last.e1rm)
    }

    /// Exercises worth swapping to: same main target muscle on the same equipment
    /// (so it is guaranteed available), ranked by mechanic then level similarity.
    static func swapCandidates(for exercise: Exercise,
                               catalog: ExerciseCatalog,
                               limit: Int = 3) -> [Exercise] {
        guard let target = exercise.primaryMuscles.first else { return [] }
        // Lower is more similar: same mechanic beats same level beats name order.
        func rank(_ candidate: Exercise) -> Int {
            (candidate.mechanic == exercise.mechanic ? 0 : 2)
                + (candidate.level == exercise.level ? 0 : 1)
        }
        return catalog.all
            .filter {
                $0.id != exercise.id
                    && $0.equipment == exercise.equipment
                    && $0.primaryMuscles.contains(target)
            }
            .sorted {
                rank($0) == rank($1)
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : rank($0) < rank($1)
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    /// The trailing non-improving run of a series, classified by the engine's
    /// thresholds: strict declines ≥ `regressionDeltas` → regression; otherwise
    /// non-improvements ≥ `plateauDeltas` → plateau. `length` counts deltas.
    private static func stallRun(in series: [Double]) -> (trend: StallTrend, length: Int)? {
        let deltas = zip(series.dropFirst(), series).map { $0 - $1 }
        var nonImproving = 0
        for delta in deltas.reversed() {
            guard delta <= 0 else { break }
            nonImproving += 1
        }
        var declining = 0
        for delta in deltas.reversed() {
            guard delta < 0 else { break }
            declining += 1
        }
        if declining >= ProgressionEngine.regressionDeltas { return (.regression, nonImproving) }
        if nonImproving >= ProgressionEngine.plateauDeltas { return (.plateau, nonImproving) }
        return nil
    }

    private static func isBackoff(from previous: Double, to current: Double) -> Bool {
        previous > 0 && current <= previous * (1 - backoffFraction)
    }
}

// MARK: - Recording to the coaching memory

extension StallDetector {

    /// Runs detection and writes the recommendation into the coaching memory — once
    /// per stall: while the same stall continues with the same response, nothing new
    /// is recorded; a fresh stall or an escalation (deload → swap) records again.
    /// The caller saves the context. Returns the log that was written, if any.
    @MainActor
    @discardableResult
    static func detectAndRecord(exId: String,
                                history: [HistoryEntry],
                                context: ModelContext,
                                catalog: ExerciseCatalog = .shared,
                                date: Date = Date()) -> CoachingLog? {
        guard let stall = detect(exId: exId, history: history) else { return nil }

        if let previous = context.coachingLogs(forExercise: exId)
            .first(where: { $0.kind == .plateau || $0.kind == .deload }),
           previous.date >= stall.stallStartDate,
           previous.payload.tags.contains(stall.response.rawValue) {
            return nil
        }

        let units = context.appSettings().units
        let exercise = catalog.exercise(id: exId)
        let name = exercise?.name ?? "This exercise"

        var metrics: [String: Double] = [
            "sessionsStalled": Double(stall.sessionsStalled),
            "lastTopWeightKg": stall.lastTopWeightKg,
            "lastTopReps": Double(stall.lastTopReps),
            "lastE1RM": Double(stall.lastE1RM),
        ]
        var tags = [stall.response.rawValue, stall.trend.rawValue]

        let kind: CoachingKind
        let summary: String
        switch stall.response {
        case .deload:
            kind = .deload
            let target = ProgressionEngine.deloadWeight(
                fromKg: stall.lastTopWeightKg,
                stepKg: Formulas.weightStepKg(units: units))
            metrics["deloadToKg"] = target
            let verb = stall.trend == .regression ? "trending down" : "stuck"
            summary = "\(name) has been \(verb) for \(stall.sessionsStalled) sessions — " +
                "deload to \(Formulas.formatWeight(kg: target, units: units)) and rebuild."
        case .swapExercise:
            kind = .plateau
            let candidates = exercise.map { swapCandidates(for: $0, catalog: catalog) } ?? []
            tags += candidates.map(\.id)
            let suggestion = candidates.first.map { "try \($0.name) instead" }
                ?? "try a similar movement instead"
            summary = stall.lastTopWeightKg == 0
                ? "\(name) reps have stalled for \(stall.sessionsStalled) sessions — \(suggestion)."
                : "\(name) is still stuck after a deload — \(suggestion)."
        }

        return context.recordCoaching(
            kind, summary: summary, date: date, exId: exId,
            payload: CoachingPayload(metrics: metrics, tags: tags))
    }
}
