//
//  DragToReorder.swift
//  Replog
//
//  Haptics for the reorderable card lists. A `List` row carrying `.onMove` lifts on a
//  long press and can then be dragged — but that gesture is invisible, so we announce
//  it: a medium impact the instant the row becomes draggable, and a soft one when the
//  move is committed. SwiftUI exposes no hook for the lift itself (`onDragSessionUpdated`
//  is macOS-only, `onMove` fires on drop), so the lift is detected with a *simultaneous*
//  long press — simultaneous so it recognises alongside the row's own drag, tap and
//  swipe actions instead of competing with them (same trick as `hideKeyboardOnTap`).
//

import SwiftUI

extension View {
    /// Buzzes when this row's long-press reorder gesture activates: "you're holding it —
    /// now drag". Put this on the row content of a `ForEach` that has `.onMove`.
    func reorderLiftFeedback() -> some View { modifier(ReorderLiftFeedback()) }

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

private struct ReorderLiftFeedback: ViewModifier {
    /// Slightly ahead of UIKit's own reorder lift so the buzz reads as the cause, not a lag.
    private static let liftDelay: TimeInterval = 0.3

    @State private var lifts = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.liftDelay).onEnded { _ in lifts += 1 }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
    }
}
