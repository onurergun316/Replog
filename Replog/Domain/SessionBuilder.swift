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
    @discardableResult
    static func start(workout: Workout, into context: ModelContext) -> ActiveSession {
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
            sessionExercise.suggestion = ProgressionEngine.recommend(
                exId: item.exId, history: history, goal: goal, units: units)

            for (setIndex, template) in item.orderedSets.enumerated() {
                let prev = previous?.sets[safe: setIndex]
                let logged = LoggedSet(
                    weightKg: template.weightKg,
                    reps: template.reps,
                    rpe: template.rpe,
                    prevWeight: prev?.w,
                    prevReps: prev?.r,
                    order: setIndex
                )
                logged.exercise = sessionExercise
                context.insert(logged)
            }
        }
        return session
    }
}

extension Array {
    /// Safe indexing that returns nil out of bounds.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
