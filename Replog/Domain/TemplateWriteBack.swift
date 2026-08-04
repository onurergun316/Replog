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

    /// What a session did that its workout never prescribed: movements added on the day,
    /// and sets logged past the prescription. Offered back to the athlete as "save this to
    /// the plan?", never applied silently.
    struct Additions: Equatable, Sendable {
        /// Exercise ids logged that the workout does not prescribe at all.
        var exerciseIds: [String] = []
        /// Completed sets logged beyond the prescribed set count, across the whole session.
        var extraSets: Int = 0

        var isEmpty: Bool { exerciseIds.isEmpty && extraSets == 0 }

        /// A short line for the prompt, e.g. "1 exercise and 2 sets".
        var summary: String {
            var parts: [String] = []
            if !exerciseIds.isEmpty {
                parts.append("\(exerciseIds.count) exercise\(exerciseIds.count == 1 ? "" : "s")")
            }
            if extraSets > 0 {
                parts.append("\(extraSets) set\(extraSets == 1 ? "" : "s")")
            }
            return parts.joined(separator: " and ")
        }
    }

    /// Everything this session added on top of `workout`'s prescription.
    ///
    /// Only *completed* sets count: a set that was added and then never logged is not a
    /// change to the workout, it is an abandoned intention.
    static func additions(session: ActiveSession, workout: Workout) -> Additions {
        let paired = matches(sessionExercises: session.exercises, items: workout.items)
        let prescribed = Set(paired.map(\.exercise.id))
        var result = Additions()

        for exercise in session.exercises.sorted(by: { $0.order < $1.order })
        where !prescribed.contains(exercise.id) {
            guard exercise.sets.contains(where: \.done) else { continue }
            if !result.exerciseIds.contains(exercise.exId) { result.exerciseIds.append(exercise.exId) }
        }
        for pair in paired {
            let prescribedOrders = Set(pair.item.sets.map(\.order))
            result.extraSets += pair.exercise.sets.filter { $0.done && !prescribedOrders.contains($0.order) }.count
        }
        return result
    }

    /// Copies every completed set's weight and reps onto the template at the same
    /// position, clearing the `estimated` flag because these are now real logged values.
    /// Templates beyond the sets logged are left untouched.
    ///
    /// `saveAdditions` decides what happens to work the plan never prescribed. The default
    /// is no: an extra set squeezed in on a good day, or a movement borrowed because a rack
    /// was busy, is a fact about *that session*, not a decision to rewrite the programme.
    /// The athlete is asked at Finish and opts in explicitly; only then do extra sets append
    /// new templates and ad hoc movements become plan items.
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
                      date: Date = Date(), saveAdditions: Bool = false) -> Int {
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
                    guard saveAdditions else { continue }
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
        if saveAdditions {
            written += adopt(session: session, into: workout, context: context, date: date)
        }
        return written
    }

    /// Adds the movements this session did but the workout never prescribed, in the order
    /// they were logged, each carrying the sets that were actually completed.
    private static func adopt(session: ActiveSession, into workout: Workout,
                              context: ModelContext, date: Date) -> Int {
        let prescribed = Set(matches(sessionExercises: session.exercises, items: workout.items)
            .map(\.exercise.id))
        var nextItemOrder = Reordering.nextOrder(after: workout.items)
        var written = 0
        for exercise in session.exercises.sorted(by: { $0.order < $1.order })
        where !prescribed.contains(exercise.id) {
            let done = exercise.orderedSets.filter(\.done)
            guard !done.isEmpty else { continue }
            let item = PlanItem(exId: exercise.exId, order: nextItemOrder)
            item.restSeconds = exercise.restSeconds
            item.workout = workout
            context.insert(item)
            nextItemOrder += 1
            for (order, logged) in done.enumerated() {
                let template = SetTemplate(weightKg: logged.weightKg, reps: logged.reps,
                                           rpe: logged.rpe, order: order, estimated: false)
                template.updatedAt = date
                template.item = item
                context.insert(template)
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
                                date: Date = Date(), saveAdditions: Bool = false) -> Int {
        guard session.isComplete,
              let workout = self.workout(for: session, context: context) else { return 0 }
        let written = apply(session: session, to: workout, context: context,
                            date: date, saveAdditions: saveAdditions)
        propagateWithinPlan(session: session, source: workout, context: context, date: date)
        return written
    }

    /// The workout a live session was built from, if it still exists.
    static func workout(for session: ActiveSession, context: ModelContext) -> Workout? {
        guard let workoutId = session.workoutId else { return nil }
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutId })
        return try? context.fetch(descriptor).first
    }

    /// What this session added beyond the workout it came from, or an empty set when the
    /// workout is gone. Convenience for the Finish flow, which asks before writing.
    static func additions(for session: ActiveSession, context: ModelContext) -> Additions {
        guard let workout = workout(for: session, context: context) else { return Additions() }
        return additions(session: session, workout: workout)
    }
}
