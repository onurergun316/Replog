//
//  TemplateBackfill.swift
//  Replog
//
//  A one-time repair for plans whose sets were logged before write-back existed.
//
//  `SessionFinisher` now copies each finished session's numbers onto its plan, but any
//  workout completed before that shipped left the plan showing the generator's original
//  estimate — so the Plans screen kept claiming 50 kg x 10 for a lift the athlete has
//  been doing at 60 kg x 8. This reconstructs exactly what write-back would have done,
//  from the history those sessions did record.
//
//  Runs once, guarded by a flag on `AppSettings`, and only touches templates still
//  flagged `estimated` — a number a human has edited, or that a finished session has
//  already written, is left alone.
//

import Foundation
import SwiftData

@MainActor
enum TemplateBackfill {

    /// Bump to re-run the repair on devices that already ran an earlier version.
    static let version = 2

    /// Applies the latest logged values to every untouched template across all plans.
    /// Returns the number of templates updated.
    @discardableResult
    static func run(context: ModelContext) -> Int {
        let settings = context.appSettings()
        // Versioned, not a bool: the first attempt gated on `estimated` and repaired
        // almost nothing, so a device that already ran it still needs this pass.
        guard settings.templateBackfillVersion < Self.version else { return 0 }
        settings.templateBackfillVersion = Self.version

        var updated = 0
        for plan in context.allPlans() {
            for workout in plan.workouts {
                for item in workout.items {
                    let history = context.history(forExercise: item.exId)
                    guard let latest = history.last else { continue }
                    updated += apply(latest: latest, to: item)
                }
            }
        }
        try? context.save()
        return updated
    }

    /// Copies a history entry's per-set values onto an item's untouched templates.
    /// Pure over the two models, so the matching rules are testable on their own.
    @discardableResult
    static func apply(latest: HistoryEntry, to item: PlanItem) -> Int {
        let sets = latest.sets
        guard !sets.isEmpty else { return 0 }
        var updated = 0
        for (index, template) in item.orderedSets.enumerated() {
            // Recency decides. A template edited *after* this session keeps its number;
            // one nobody has touched since takes the logged value.
            guard template.supersededBy(latest.date), let recorded = sets[safe: index] else { continue }
            template.weightKg = recorded.w
            template.reps = recorded.r
            template.estimated = false
            template.updatedAt = latest.date
            updated += 1
        }
        return updated
    }
}
