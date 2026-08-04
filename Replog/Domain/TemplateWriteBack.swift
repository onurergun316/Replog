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
//  SCOPE: a plan. The numbers propagate to every workout *in the same plan* that prescribes
//  the same movement, so a plan stays internally consistent — train bench on Monday and the
//  Thursday workout that also benches starts from what you just lifted. They never cross into
//  another plan: that plan is a different program with its own working loads, and
//  `history(forExercise:inPlan:)` keeps its trail separate too.
//
//  A caveat worth knowing: a plan that deliberately prescribes the same lift at two
//  intensities (a heavy day at 100x5 and a volume day at 70x12) will have the volume day
//  overwritten by the heavy day's numbers, because within a plan the last log wins. Split
//  those across two plans, or use different variations, if you want them to diverge.
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

    /// Copies every completed set's weight and reps onto the template at the same
    /// position, clearing the `estimated` flag because these are now real logged values.
    /// Sets logged beyond the prescription (the athlete tapped "Add set") append new
    /// templates; templates beyond the sets logged are left untouched.
    ///
    /// **RPE is deliberately not written back.** The template's RPE is the *target*
    /// effort the program prescribed; the logged RPE is how hard the set actually felt.
    /// Copying felt over target would silently re-prescribe the workout — and
    /// `ProgressionEngine` reads that target to calibrate a first-session load estimate
    /// (`SessionBuilder` passes it as `targetRPE`), so an honest "that was a 10" would
    /// permanently redefine the program as an RPE-10 program.
    ///
    /// Matching is by `LoggedSet.order`, not array position, so a set deleted mid-session
    /// doesn't slide every later set onto the wrong template.
    ///
    /// Returns the number of template sets written, for tests and telemetry.
    @discardableResult
    static func apply(session: ActiveSession, to workout: Workout, context: ModelContext,
                      date: Date = Date()) -> Int {
        var written = 0
        for (exercise, item) in matches(sessionExercises: session.exercises, items: workout.items) {
            let templatesByOrder = Dictionary(item.orderedSets.map { ($0.order, $0) },
                                              uniquingKeysWith: { first, _ in first })
            var nextOrder = Reordering.nextOrder(after: item.sets)
            for logged in exercise.orderedSets where logged.done {
                if let template = templatesByOrder[logged.order] {
                    template.weightKg = logged.weightKg
                    template.reps = logged.reps
                    template.estimated = false
                    template.updatedAt = date
                } else {
                    let template = SetTemplate(weightKg: logged.weightKg, reps: logged.reps,
                                               rpe: logged.rpe, order: nextOrder, estimated: false)
                    template.updatedAt = date
                    template.item = item
                    context.insert(template)
                    nextOrder += 1
                }
                written += 1
            }
        }
        return written
    }

    /// Mirrors the session's logged numbers onto the *other* workouts of the same plan that
    /// prescribe the same movement, so one plan holds one working load per movement.
    ///
    /// Occurrence-matched, exactly like `matches`: the second "Bench Press" of the session
    /// writes to the second "Bench Press" of a sibling workout, not to both. Only session
    /// exercises that were part of the source prescription propagate — an exercise added ad
    /// hoc mid-workout was never in the plan and must not silently appear in another workout.
    ///
    /// Unlike the source workout, a sibling never *grows*: extra sets logged beyond the
    /// prescription append there but not here, because "I did a fifth set on Monday" is not
    /// a statement about Thursday's prescription. Sibling templates edited more recently than
    /// this session are left alone (`supersededBy`), so a deliberate edit always outranks a
    /// mirrored number.
    @discardableResult
    static func propagateWithinPlan(session: ActiveSession, source: Workout,
                                    context: ModelContext, date: Date = Date()) -> Int {
        guard let plan = source.plan else { return 0 }
        // Only what the source workout actually prescribed, grouped in occurrence order.
        var byExercise: [String: [SessionExercise]] = [:]
        for pair in matches(sessionExercises: session.exercises, items: source.items) {
            byExercise[pair.exercise.exId, default: []].append(pair.exercise)
        }
        guard !byExercise.isEmpty else { return 0 }

        var written = 0
        for sibling in plan.workouts where sibling.id != source.id {
            let itemsByExercise = Dictionary(grouping: sibling.orderedItems, by: \.exId)
            for (exId, exercises) in byExercise {
                guard let items = itemsByExercise[exId] else { continue }
                for (occurrence, item) in items.enumerated() {
                    guard let exercise = exercises[safe: occurrence] else { break }
                    written += mirror(exercise, onto: item, date: date)
                }
            }
        }
        return written
    }

    /// Copies one session exercise's completed sets onto an existing template at the same
    /// set order. Never inserts, never deletes. Returns how many templates it wrote.
    private static func mirror(_ exercise: SessionExercise, onto item: PlanItem, date: Date) -> Int {
        let templatesByOrder = Dictionary(item.orderedSets.map { ($0.order, $0) },
                                          uniquingKeysWith: { first, _ in first })
        var written = 0
        for logged in exercise.orderedSets where logged.done {
            guard let template = templatesByOrder[logged.order],
                  template.supersededBy(date) else { continue }
            template.weightKg = logged.weightKg
            template.reps = logged.reps
            template.estimated = false
            template.updatedAt = date
            written += 1
        }
        return written
    }

    /// Resolves the workout a session was built from, writes its logged values back, and
    /// mirrors them across the rest of that plan. No-op when the workout is incomplete, or
    /// when the session has no source workout (or it has since been deleted), so callers can
    /// invoke this unconditionally.
    @discardableResult
    static func applyIfComplete(session: ActiveSession, context: ModelContext,
                                date: Date = Date()) -> Int {
        guard session.isComplete, let workoutId = session.workoutId else { return 0 }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })
        guard let workout = try? context.fetch(descriptor).first else { return 0 }
        let written = apply(session: session, to: workout, context: context, date: date)
        propagateWithinPlan(session: session, source: workout, context: context, date: date)
        return written
    }
}
