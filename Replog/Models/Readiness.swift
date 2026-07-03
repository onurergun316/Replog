//
//  Readiness.swift
//  Replog
//
//  A stored subjective readiness check-in (sleep, soreness, stress) captured at session
//  start. Persisted so the coach can spot recurring patterns across the week. The pure
//  mapping to a session modulation lives in `Domain/ReadinessModulator`.
//

import Foundation
import SwiftData

@Model
final class ReadinessEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Stored as `ReadinessRating.rawValue` (0 good … 2 poor).
    var sleepRaw: Int = 0
    var sorenessRaw: Int = 0
    var stressRaw: Int = 0

    init(date: Date = Date(), sleep: ReadinessRating, soreness: ReadinessRating, stress: ReadinessRating) {
        self.date = date
        self.sleepRaw = sleep.rawValue
        self.sorenessRaw = soreness.rawValue
        self.stressRaw = stress.rawValue
    }

    var sleep: ReadinessRating { ReadinessRating(rawValue: sleepRaw) ?? .good }
    var soreness: ReadinessRating { ReadinessRating(rawValue: sorenessRaw) ?? .good }
    var stress: ReadinessRating { ReadinessRating(rawValue: stressRaw) ?? .good }

    /// The value-typed check-in this row represents.
    var checkIn: ReadinessCheckIn {
        ReadinessCheckIn(sleep: sleep, soreness: soreness, stress: stress)
    }
}
