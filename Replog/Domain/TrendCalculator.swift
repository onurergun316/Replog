//
//  TrendCalculator.swift
//  Replog
//
//  Finance-style up/down/flat comparison of a logged value against the same set
//  index from the previous session.
//

import Foundation

/// Direction of a logged value vs the same set last session.
///
/// A pure domain value: it says which way a number moved, and nothing about how that looks.
/// The arrow glyph and colour it renders as live in an extension in `DesignSystem/Components`,
/// so the comparison logic stays testable without SwiftUI.
enum Trend: Equatable, Sendable {
    case up, down, flat, none
}

enum TrendCalculator {
    /// Compares a current value to a previous one.
    /// `nil` previous (no prior session) yields `.none` (no arrow shown).
    static func trend(current: Double, previous: Double?) -> Trend {
        guard let previous else { return .none }
        if current > previous { return .up }
        if current < previous { return .down }
        return .flat
    }

    /// Percentage change current vs previous, or nil when there's no baseline.
    static func percentChange(current: Double, previous: Double?) -> Double? {
        guard let previous, previous != 0 else { return nil }
        return (current - previous) / previous * 100
    }
}
