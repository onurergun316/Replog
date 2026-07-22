//
//  DragSelectGesture.swift
//  Replog
//
//  The calendar grid's long-press-then-drag selection, as a real UIKit
//  `UILongPressGestureRecognizer` bridged via `UIGestureRecognizerRepresentable`.
//  A SwiftUI `LongPressGesture` would win the touch race against the scroll views
//  without arbitrating (the reorder-lift lesson — see `DragToReorder.swift`); the
//  UIKit recognizer participates in the system's arbitration, so scrolling and month
//  paging win when the finger moves early, and the press wins only on a genuine hold.
//

import SwiftUI
import UIKit

struct DragSelectGesture: UIGestureRecognizerRepresentable {
    /// Called with the touch point in the attached view's coordinate space.
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        recognizer.allowableMovement = .greatestFiniteMagnitude // the drag IS the gesture
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer,
                                         context: Context) {
        let point = context.converter.localLocation
        switch recognizer.state {
        case .began: onBegan(point)
        case .changed: onMoved(point)
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }
}
