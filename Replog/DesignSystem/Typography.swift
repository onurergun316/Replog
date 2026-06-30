//
//  Typography.swift
//  Replog
//
//  SF Rounded type scale from the spec (titles 30/900, big numbers 24-60,
//  card titles 16-18/800, body 15, labels 11-13/800 uppercase). Tabular figures
//  for all numbers/timers.
//

import SwiftUI

extension Font {
    /// Rounded system font at a given size/weight.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // Named scale
    static let screenTitle = rounded(30, .black)
    static let cardTitle   = rounded(17, .heavy)
    static let bodyText    = rounded(15, .semibold)
    static let metric      = rounded(24, .black)
    static let bigMetric   = rounded(46, .black)
}

extension View {
    /// Uppercase section/eyebrow label (11-13/800, wide tracking).
    func eyebrow(_ size: CGFloat = 12) -> some View {
        self
            .font(.rounded(size, .heavy))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.text2)
    }

    /// Tabular figures for stable-width numbers, timers, and steppers.
    func tabularNumbers() -> some View {
        self.monospacedDigit()
    }
}
