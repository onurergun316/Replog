//
//  RestTimerModel.swift
//  Replog
//
//  Owns the between-sets rest timer for the active workout: a countdown to an end
//  date plus the total it was started with (drives the ring). Pure, testable state —
//  the view renders it via a TimelineView.
//

import Foundation
import Observation

@MainActor
@Observable
final class RestTimerModel {
    /// When the current rest ends; `nil` when no timer is running.
    private(set) var endDate: Date?
    /// The duration the current timer was (re)started with, in seconds.
    private(set) var total: Int = 0

    var isRunning: Bool { endDate != nil }

    /// (Re)starts the timer for `seconds`, replacing any running countdown.
    func start(seconds: Int) {
        total = max(1, seconds)
        endDate = Date().addingTimeInterval(TimeInterval(total))
    }

    /// Adds/removes time (min 15s total) while a timer is running.
    func adjust(_ delta: Int, now: Date = Date()) {
        guard let end = endDate else { return }
        total = max(15, total + delta)
        endDate = max(now, end.addingTimeInterval(TimeInterval(delta)))
    }

    func skip() { endDate = nil }

    /// Whole seconds left at `date` (0 when idle or elapsed).
    func remaining(at date: Date) -> Int {
        guard let end = endDate else { return 0 }
        return max(0, Int(end.timeIntervalSince(date).rounded(.up)))
    }

    /// Fraction of the ring still full at `date` (0…1).
    func fraction(at date: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(remaining(at: date)) / Double(total)))
    }
}
