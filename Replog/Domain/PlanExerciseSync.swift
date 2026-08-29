//
//  PlanExerciseSync.swift
//  Replog
//
//  One plan holds ONE prescription per movement.
//
//  A plan that benches on Monday and again on Thursday is prescribing the same lift twice,
//  not two unrelated lifts. So editing it in either place — a heavier top set, an extra
//  rep, a fourth set — is a statement about the movement inside that plan, and it lands on
//  every workout of that plan that prescribes it.
//
//  It never crosses a plan boundary. A second plan is a different programme with its own
//  working loads, and `history(forExercise:inPlan:)` keeps its trail separate for exactly
//  the same reason. Plan A's bench and Plan B's bench are two different prescriptions that
//  happen to share a catalog id.
//
//  This is the *manual editing* half of a rule the app already applied to logged numbers:
//  `TemplateWriteBack.propagateWithinPlan` spreads what a finished session lifted across
//  the same plan. Without this half, an edit in the Workout Editor stayed on the day it was
//  made and the plan contradicted itself until the next session repaired it.
//
//  Occurrence-matched, exactly like `TemplateWriteBack.matches`: a workout that prescribes
//  the same movement twice (a top set, then a back-off block) keeps them distinct — the
//  first bench mirrors onto the first bench, the second onto the second — rather than
//  collapsing both onto one prescription.
//

import Foundation
import SwiftData

@MainActor
enum PlanExerciseSync {

    /// Which occurrence of its own movement `item` is inside its workout: 0 for the only
    /// (or first) bench press, 1 for a second one, and so on. `nil` when the item has no
    /// workout — an orphan can't be positioned.
    static func occurrenceIndex(of item: PlanItem) -> Int? {
        guard let workout = item.workout else { return nil }
        return workout.orderedItems.filter { $0.exId == item.exId }
            .firstIndex { $0.id == item.id }
    }

    /// Every item elsewhere in the same plan that prescribes the same movement at the same
    /// occurrence index — the items an edit to `item` is also an edit to.
    ///
    /// Empty when the item is orphaned, its workout has no plan, or no other workout in the
    /// plan trains the movement (or trains it fewer times than this workout does).
    static func siblings(of item: PlanItem) -> [PlanItem] {
        guard let workout = item.workout, let plan = workout.plan,
              let occurrence = occurrenceIndex(of: item) else { return [] }
        return plan.orderedWorkouts
            .filter { $0.id != workout.id }
            .compactMap { sibling in
                sibling.orderedItems.filter { $0.exId == item.exId }[safe: occurrence]
            }
    }

    /// Copies `item`'s set prescription onto each of its siblings, so the plan agrees with
    /// itself. Returns the number of *items* changed, for tests and call-site assertions.
    ///
    /// The copy is verbatim — weight, reps, RPE, the `estimated` flag and `updatedAt`, and
    /// the set's own `order` — and the sibling's set count is made to match, appending what
    /// is missing and deleting what is surplus. Anything less than an exact copy leaves the
    /// two days subtly disagreeing, which is the bug this exists to remove: mirroring only
    /// the numbers would leave "I added a fourth set on Monday" invisible on Thursday.
    ///
    /// Carrying `updatedAt` across matters beyond tidiness. It is what `SetTemplate
    /// .supersededBy` reads to decide whether a finished session may overwrite a number, so
    /// a mirrored edit has to outrank an older log on the sibling day exactly as it does on
    /// the day it was typed.
    ///
    /// The caller saves the context, matching every other write in the editor — and, when
    /// the edit was a *deletion*, saves before calling too. A pending delete is still on the
    /// relationship SwiftData hands back, so mirroring a not-yet-saved removal would read
    /// the set as still prescribed and copy it straight back onto the sibling.
    @discardableResult
    static func mirror(_ item: PlanItem, context: ModelContext) -> Int {
        let source = item.orderedSets
        var changed = 0
        for sibling in siblings(of: item) {
            if apply(source, to: sibling, context: context) { changed += 1 }
        }
        return changed
    }

    /// Makes `target` prescribe exactly `source`. Returns whether anything actually moved,
    /// so a no-op mirror doesn't report a change it didn't make.
    private static func apply(_ source: [SetTemplate], to target: PlanItem,
                              context: ModelContext) -> Bool {
        var changed = false
        let existing = target.orderedSets

        for (index, template) in source.enumerated() {
            if let current = existing[safe: index] {
                guard !current.matches(template) else { continue }
                current.weightKg = template.weightKg
                current.reps = template.reps
                current.rpe = template.rpe
                current.order = template.order
                current.estimated = template.estimated
                current.updatedAt = template.updatedAt
            } else {
                let copy = SetTemplate(weightKg: template.weightKg, reps: template.reps,
                                       rpe: template.rpe, order: template.order,
                                       estimated: template.estimated)
                copy.updatedAt = template.updatedAt
                copy.item = target
                context.insert(copy)
            }
            changed = true
        }

        // Surplus sets on the sibling: the source no longer prescribes them.
        for surplus in existing.dropFirst(source.count) {
            context.delete(surplus)
            changed = true
        }
        return changed
    }
}

extension SetTemplate {
    /// Whether this template already prescribes exactly what `other` does. Compared on the
    /// values a mirror copies — identity and relationships are deliberately not part of it.
    func matches(_ other: SetTemplate) -> Bool {
        weightKg == other.weightKg && reps == other.reps && rpe == other.rpe
            && order == other.order && estimated == other.estimated && updatedAt == other.updatedAt
    }
}
