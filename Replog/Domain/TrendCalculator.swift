//
//  TrendCalculator.swift
//  Replog
//
//  Finance-style up/down/flat comparison of a logged value against the same set
//  index from the previous session.
//

import Foundation

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
