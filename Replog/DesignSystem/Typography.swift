//
//  Typography.swift
//  Replog
//
//  SF Rounded type scale. Call sites pass the spec's *semantic* emphasis (up to
//  .black); the rendered weight goes through a refined scale — display caps at bold
//  (700), UI emphasis at semibold (600) — because SF Rounded's counters close up at
//  800–900 and legibility research puts glanceable UI text in the 400–700 band, with
//  hierarchy carried by size rather than uniform maximum weight. The mapping is
//  monotonic (never inverts two call sites) and lives in exactly one place, so the
//  whole app's voice is tuned here. Tabular figures for all numbers/timers.
//

import SwiftUI

extension Font {
    /// Rounded system font at a given size and semantic weight (see header).
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: rendered(weight), design: .rounded)
    }

    /// The refined weight scale: 900→700, 800/700→600, lighter weights unchanged.
    private static func rendered(_ weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .black: return .bold
        case .heavy, .bold: return .semibold
        default: return weight
        }
    }

    // Named scale
    static let screenTitle = rounded(30, .black)
    static let cardTitle   = rounded(17, .heavy)
    static let bodyText    = rounded(15, .semibold)
    static let metric      = rounded(24, .black)
    static let bigMetric   = rounded(46, .black)
}

extension View {
    /// Uppercase section/eyebrow label (11-13, wide tracking).
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
