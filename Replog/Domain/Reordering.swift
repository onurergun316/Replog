//
//  Reordering.swift
//  Replog
//
//  Drag-to-reorder math for the plan editors. SwiftUI's `onMove` reports the dragged
//  offsets plus a destination measured against the list *before* the move; `moved`
//  turns that into the new sequence and `apply` writes it back as a contiguous 0-based
//  `order`. Pure Foundation — SwiftUI's own `move(fromOffsets:toOffset:)` lives in
//  SwiftUICore, which the Domain layer deliberately doesn't import.
//

import Foundation

/// A model whose position in a list is the user's to choose.
protocol Orderable: AnyObject {
    var order: Int { get set }
}

extension Plan: Orderable {}
extension Workout: Orderable {}
extension PlanItem: Orderable {}
extension SetTemplate: Orderable {}
extension SessionExercise: Orderable {}
extension LoggedSet: Orderable {}

enum Reordering {

    /// `items` with everything at `source` lifted out and re-inserted before `destination`.
    /// `destination` follows SwiftUI's `onMove` convention — it indexes the pre-move list,
    /// so dragging a row downwards arrives one past its final slot. Stale/out-of-range
    /// offsets are ignored rather than trapping.
    static func moved<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        let lifted = source.sorted().filter { items.indices.contains($0) }
        guard !lifted.isEmpty else { return items }
        let moving = lifted.map { items[$0] }
        let liftedSet = Set(lifted)
        let rest = items.indices.filter { !liftedSet.contains($0) }.map { items[$0] }
        let above = lifted.filter { $0 < destination }.count
        let insertAt = min(max(destination - above, 0), rest.count)
        return Array(rest[..<insertAt]) + moving + Array(rest[insertAt...])
    }

    /// Applies a drag move to `items` (which must already be in display order) and
    /// renumbers every `order` to 0..<n — which also heals duplicate or gapped orders
    /// left behind by older data. Returns whether anything actually changed, so callers
    /// only save (and buzz) on a real move.
    @discardableResult
    static func apply<T: Orderable>(from source: IndexSet, to destination: Int, in items: [T]) -> Bool {
        var changed = false
        for (index, item) in moved(items, from: source, to: destination).enumerated() where item.order != index {
            item.order = index
            changed = true
        }
        return changed
    }

    /// The order for a newly appended item: one past the highest in use. Using the
    /// collection's `count` instead would collide with an existing order after a delete.
    static func nextOrder<T: Orderable>(after items: [T]) -> Int {
        (items.map(\.order).max() ?? -1) + 1
    }
}
