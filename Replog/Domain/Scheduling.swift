//
//  Scheduling.swift
//  Replog
//
//  Weekday assignment for adding workouts to a plan. New days prefer the classic
//  Mon/Wed/Fri cadence, then fill remaining days; taken days are never reused.
//

import Foundation

enum WeekdayPlanner {
    /// Preference order when auto-assigning a new workout's day.
    static let preferred: [Weekday] = [.mon, .wed, .fri, .sun, .tue, .thu, .sat]

    /// The first free weekday not already used, in preference order. Nil if all 7 taken.
    static func firstFreeDay(excluding used: Set<Weekday>) -> Weekday? {
        preferred.first { !used.contains($0) }
    }

    /// Whether a day can be chosen given the days used by *other* workouts.
    static func isAvailable(_ day: Weekday, usedByOthers used: Set<Weekday>) -> Bool {
        !used.contains(day)
    }
}
