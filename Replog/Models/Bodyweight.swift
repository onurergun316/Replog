//
//  Bodyweight.swift
//  Replog
//
//  The bodyweight time series, appended by the periodic check-in (one entry per
//  calendar day; re-logging the same day updates it). Like `HistoryEntry`, a flat
//  queryable record — it drives the Today trend card and feeds the weekly report.
//

import Foundation
import SwiftData

@Model
final class BodyweightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Stored in kilograms; display conversion happens at the edge (`Formulas`).
    var weightKg: Double = 0

    init(weightKg: Double, date: Date = Date()) {
        self.weightKg = weightKg
        self.date = date
    }
}
