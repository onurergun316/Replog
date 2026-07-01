//
//  KeyboardDismiss.swift
//  Replog
//
//  App-wide keyboard dismissal. Number/decimal pads have no return key, so tapping
//  away (or scrolling) must dismiss the keyboard everywhere.
//

import SwiftUI

extension View {
    /// Dismisses the keyboard when the user taps anywhere in this view's area.
    /// Uses a *simultaneous* tap so it never steals taps from buttons or fields — it
    /// just also resigns first responder, which is exactly the desired behavior.
    func hideKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded { KeyboardDismiss.resign() }
        )
    }
}

enum KeyboardDismiss {
    /// Resigns the current first responder (dismisses the keyboard).
    static func resign() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
