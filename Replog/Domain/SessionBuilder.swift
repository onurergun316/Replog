//
//  SessionBuilder.swift
//  Replog
//
//  Creates a live ActiveSession from a Workout's prescribed sets, pre-filling each
//  set with the "previous" weight/reps from the same set index last session and
//  attaching the ProgressionEngine's next-session suggestion per exercise.
//

import Foundation
import SwiftData

@MainActor
enum SessionBuilder {

    /// Builds and inserts an ActiveSession for `workout`. The caller saves the context.
    /// When a `readiness` check-in is supplied, its modulation is applied to the built session
    /// (trimming the last set of each exercise when fatigue is high) and its reason is stored
    /// on `session.readinessNote`. Passing `nil` (the default) leaves the session untouched.
    @discardableResult
    static func start(workout: Workout, into context: ModelContext,
                      readiness: ReadinessCheckIn? = nil) -> ActiveSession {
        let planName = workout.plan?.name ?? ""
        let session = ActiveSession(workoutId: workout.id, name: workout.name, planName: planName)
        context.insert(session)

        let goal = context.userProfile().goal
        let units = context.appSettings().units

        for (exIndex, item) in workout.orderedItems.enumerated() {
            let sessionExercise = SessionExercise(exId: item.exId, order: exIndex)
            sessionExercise.restSeconds = item.restSeconds
            sessionExercise.session = session
            context.insert(sessionExercise)

            let history = context.history(forExercise: item.exId)
            let previous = history.last
            // Pass the plan's prescribed RPE so a first-session estimate calibrates to the
            // athlete's real logged effort (see ProgressionEngine + LoadCalibrator).
            sessionExercise.suggestion = ProgressionEngine.recommend(
                exId: item.exId, history: history, goal: goal, units: units,
                targetRPE: item.orderedSets.first?.rpe)

            for (setIndex, template) in item.orderedSets.enumerated() {
                let prev = previous?.sets[safe: setIndex]
                // Start from what was actually lifted last time.
                //
                // `SessionFinisher` normally writes logged values back onto the template,
                // so the two agree. This covers every case where it couldn't: sessions
                // finished before write-back existed, partial finishes, and a plan whose
                // exercise was swapped. `estimated` is the guard — it means the number is
                // still a computed seed nobody has touched, so history is strictly better
                // information. Once a human edits the template, or a finished session
                // writes to it, the flag clears and the template wins.
                let seed = template.estimated ? prev : nil
                let logged = LoggedSet(
                    weightKg: seed?.w ?? template.weightKg,
                    reps: seed?.r ?? template.reps,
                    rpe: template.rpe,
                    prevWeight: prev?.w,
                    prevReps: prev?.r,
                    estimated: template.estimated && seed == nil,
                    order: setIndex
                )
                logged.exercise = sessionExercise
                context.insert(logged)
            }
        }

        if let readiness {
            apply(readiness, to: session, context: context)
        }
        return session
    }

    /// Applies a readiness modulation to a freshly-built session: trims the last set of each
    /// multi-set exercise when fatigue is high, and always records the reason on the session.
    private static func apply(_ readiness: ReadinessCheckIn, to session: ActiveSession,
                              context: ModelContext) {
        let modulation = ReadinessModulator.modulation(for: readiness)
        session.readinessNote = ReadinessModulator.reason(for: readiness, modulation: modulation)
        guard modulation.reducesVolume else { return }
        for exercise in session.exercises {
            let ordered = exercise.orderedSets
            guard ordered.count > 1, let last = ordered.last else { continue }
            context.delete(last)
        }
    }
}

extension Array {
    /// Safe indexing that returns nil out of bounds.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
