//
//  Scheduling.swift
//  Replog
//
//  Weekday assignment for adding workouts to a plan (`WeekdayPlanner`), plus moving
//  through the Sun…Sat week strip on Today (`WeekBrowser`). New days prefer the classic
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

/// Moving between days on the Today screen. Swiping the hero card jumps straight to the
/// next day that actually has a workout — landing on each intervening rest day would be
/// three swipes to see Friday on a Mon/Wed/Fri plan. Tapping the strip still selects any
/// day exactly. The week doesn't wrap: Sun…Sat is one screenful with two ends.
enum WeekBrowser {

    /// The nearest `scheduled` day after `day` in Sun…Sat order, or nil at the end of the week.
    static func next(after day: Weekday, scheduled: Set<Weekday>) -> Weekday? {
        step(from: day, forward: true, scheduled: scheduled)
    }

    /// The nearest `scheduled` day before `day` in Sun…Sat order, or nil at the start of the week.
    static func previous(before day: Weekday, scheduled: Set<Weekday>) -> Weekday? {
        step(from: day, forward: false, scheduled: scheduled)
    }

    private static func step(from day: Weekday, forward: Bool, scheduled: Set<Weekday>) -> Weekday? {
        let week = Weekday.allCases
        guard let index = week.firstIndex(of: day) else { return nil }
        let candidates = forward ? Array(week[(index + 1)...]) : week[..<index].reversed()
        return candidates.first { scheduled.contains($0) }
    }
}
