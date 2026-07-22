//
//  DragToReorder.swift
//  Replog
//
//  Support for the reorderable card lists (`List` rows under a ForEach with `.onMove`).
//  Hard-learned rule: attach NO custom gesture to a reorderable row. The reorder lift is
//  a UIKit recognizer on the List's backing collection-view cell, and SwiftUI's
//  `simultaneousGesture` composes only with *SwiftUI* gestures — a row-level long press
//  recognises inside the lift window, steals the touch, and the row never lifts (observed
//  on device; the system draws and announces the lift itself). So this file only adds
//  what cannot compete for a touch: a haptic after the drop, and accessibility actions.
//

import SwiftUI

extension View {
    /// Confirms a committed reorder. Drive `trigger` from a counter bumped inside `onMove`.
    func reorderCommitFeedback(trigger: Int) -> some View {
        sensoryFeedback(.impact(flexibility: .soft), trigger: trigger)
    }

    /// Exposes the drag as VoiceOver / Switch Control rotor actions, since a long-press
    /// drag is unreachable with either. `move` takes the same `(IndexSet, Int)` as
    /// `onMove`, so a row hands it the very handler its `ForEach` already uses — note the
    /// `+2` for "down", which is `onMove`'s pre-move destination convention.
    func reorderAccessibilityActions(index: Int, count: Int,
                                     move: @escaping (IndexSet, Int) -> Void) -> some View {
        accessibilityActions {
            if index > 0 {
                Button("Move up") { move(IndexSet(integer: index), index - 1) }
            }
            if index < count - 1 {
                Button("Move down") { move(IndexSet(integer: index), index + 2) }
            }
        }
    }
}
