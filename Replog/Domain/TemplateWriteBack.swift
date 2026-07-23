//
//  TemplateWriteBack.swift
//  Replog
//
//  Carrying a finished session's numbers back onto the plan. The templates are the
//  athlete's *current working numbers*, not a frozen prescription: what you actually
//  lifted last time is what the next session — and the Workout Editor — starts from.
//
//  Only a fully completed workout writes back (a partial session is not evidence that
//  the prescription changed), and only ever *upwards* into the sets you logged: surplus
//  templates are left alone, so a readiness-trimmed session can't permanently shrink
//  the plan.
//

import Foundation
import SwiftData

@MainActor
enum TemplateWriteBack {

    /// Pairs each session exercise with the plan item it was built from.
    ///
    /// Matching is by `exId`, and a workout that prescribes the same exercise twice
    /// (e.g. a top set then a back-off block) consumes its items in `order`, so the
    /// second occurrence writes to the second item rather than both landing on the first.
    /// Session exercises with no matching item — anything added ad hoc mid-workout —
    /// are skipped: they were never part of the plan and must not mutate it.
    static func matches(sessionExercises: [SessionExercise],
                        items: [PlanItem]) -> [(exercise: SessionExercise, item: PlanItem)] {
        var pool = Dictionary(grouping: items.sorted { $0.order < $1.order }, by: \.exId)
            .mapValues { $0[...] }
        var result: [(exercise: SessionExercise, item: PlanItem)] = []
        for exercise in sessionExercises.sorted(by: { $0.order < $1.order }) {
            guard var remaining = pool[exercise.exId], let item = remaining.popFirst() else { continue }
            pool[exercise.exId] = remaining
            result.append((exercise, item))
        }
        return result
    }

    /// Copies every completed set's weight/reps/RPE onto the template at the same
    /// position, clearing the `estimated` flag because these are now real logged values.
    /// Sets logged beyond the prescription (the athlete tapped "Add set") append new
    /// templates; templates beyond the sets logged are left untouched.
    ///
    /// Returns the number of template sets written, for tests and telemetry.
    @discardableResult
    static func apply(session: ActiveSession, to workout: Workout, context: ModelContext) -> Int {
        var written = 0
        for (exercise, item) in matches(sessionExercises: session.exercises, items: workout.items) {
            let templates = item.orderedSets
            var nextOrder = Reordering.nextOrder(after: item.sets)
            for (index, logged) in exercise.orderedSets.enumerated() where logged.done {
                if index < templates.count {
                    let template = templates[index]
                    template.weightKg = logged.weightKg
                    template.reps = logged.reps
                    template.rpe = logged.rpe
                    template.estimated = false
                } else {
                    let template = SetTemplate(weightKg: logged.weightKg, reps: logged.reps,
                                               rpe: logged.rpe, order: nextOrder, estimated: false)
                    template.item = item
                    context.insert(template)
                    nextOrder += 1
                }
                written += 1
            }
        }
        return written
    }

    /// Resolves the workout a session was built from and writes its logged values back.
    /// No-op when the workout is incomplete, when the session has no source workout
    /// (or it has since been deleted), so callers can invoke this unconditionally.
    @discardableResult
    static func applyIfComplete(session: ActiveSession, context: ModelContext) -> Int {
        guard session.isComplete, let workoutId = session.workoutId else { return 0 }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })
        guard let workout = try? context.fetch(descriptor).first else { return 0 }
        return apply(session: session, to: workout, context: context)
    }
}
