//
//  StreakEngine.swift
//  Replog
//
//  Schedule-aware streaks over binary days. A day is "done" when ANY workout was fully
//  completed that day — it doesn't matter which weekday the workout was assigned to,
//  or whether it was a day-less Extra; finishing twice still counts once:
//
//   • Workout streak — every done day counts (+1), scheduled or not. The run breaks at
//     a *past* scheduled weekday that ended with nothing done. Undone rest days pass
//     through silently; today's scheduled workout, while still undone, gets grace.
//     With no schedule at all (extras-only), it's plain consecutive done days.
//
//   • Week streak — consecutive "perfect weeks": every scheduled day of the week done
//     (by any workout). A missed scheduled day breaks both streaks; extras on rest
//     days boost the workout streak but can't perfect a week.
//
//  All functions are pure (no SwiftData), so they're fully unit-testable.
//

import Foundation

enum StreakEngine {

    /// Distinct weekdays that have at least one scheduled workout across the given plans.
    /// "Extra" workouts are day-less by definition, so they never create a scheduled day.
    static func scheduledDays(in plans: [Plan]) -> Set<Weekday> {
        Set(plans.flatMap(\.workouts).filter { !$0.isExtra }.map(\.day))
    }

    /// Consecutive done days, counting back from `today`. Every day with a completed
    /// workout counts — scheduled or not, whichever workout it was. The run stops at
    /// the first *past* scheduled weekday with nothing done; undone rest days pass
    /// through. Today's scheduled workout, while still due, is grace — not a miss.
    /// With an empty schedule (extras-only), every day is "expected", which degrades
    /// to plain consecutive done days.
    static func workoutStreak(
        scheduledDays: Set<Weekday>,
        doneDates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        guard !doneDays.isEmpty else { return 0 }
        let required = scheduledDays.isEmpty ? Set(Weekday.allCases) : scheduledDays

        let startOfToday = calendar.startOfDay(for: today)
        var cursor = startOfToday
        var count = 0
        // Safety bound: never walk more than ~2 years of days.
        for _ in 0..<732 {
            if doneDays.contains(cursor) {
                count += 1
            } else if required.contains(Weekday.from(cursor, calendar: calendar)),
                      cursor != startOfToday {
                break // a past required day ended with nothing done — streak ends here
            }
            // else: rest day with nothing done, or today still due — pass through.
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            // Once we're older than every completion, the next required day is a miss.
            if let earliest = doneDays.min(), cursor < earliest { break }
        }
        return count
    }

    /// Consecutive "perfect weeks" ending at the current week.
    ///
    /// • The current week counts as in-progress (+1) when every *elapsed* scheduled
    ///   workout (on or before today) is done and at least one has been done. If an
    ///   elapsed scheduled workout this week was missed, the whole streak is broken (0).
    /// • Each prior week counts only if *all* of its scheduled workouts were completed.
    static func weekStreak(
        scheduledDays: Set<Weekday>,
        doneDates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !scheduledDays.isEmpty else { return 0 }
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        let startOfToday = calendar.startOfDay(for: today)
        guard let thisWeekStart = startOfWeek(for: startOfToday, calendar: calendar) else { return 0 }

        var weeks = 0

        // Current (in-progress) week.
        let scheduledThisWeek = scheduledDates(weekStart: thisWeekStart, scheduledDays: scheduledDays, calendar: calendar)
        // A *past* scheduled workout (before today) left undone is a miss → breaks both streaks.
        // Today's scheduled workout, while still due, gets the same grace as the workout streak.
        let pastScheduled = scheduledThisWeek.filter { $0 < startOfToday }
        if pastScheduled.contains(where: { !doneDays.contains($0) }) {
            return 0
        }
        let doneThisWeek = scheduledThisWeek.filter { $0 <= startOfToday && doneDays.contains($0) }
        if !doneThisWeek.isEmpty {
            weeks += 1 // On track with at least one scheduled workout done.
        }

        // Prior weeks: require every scheduled workout completed.
        guard var cursor = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) else { return weeks }
        for _ in 0..<104 { // ~2 years of weeks
            let scheduled = scheduledDates(weekStart: cursor, scheduledDays: scheduledDays, calendar: calendar)
            guard !scheduled.isEmpty, scheduled.allSatisfy({ doneDays.contains($0) }) else { break }
            weeks += 1
            guard let prev = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = prev
        }
        return weeks
    }

    // MARK: - Helpers

    /// The Sunday that starts the week containing `date` (matches the Today week strip).
    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        let weekdayIndex = calendar.component(.weekday, from: startOfDay) - 1 // 0 = Sunday
        return calendar.date(byAdding: .day, value: -weekdayIndex, to: startOfDay)
    }

    /// The concrete dates of the scheduled weekdays within the week starting `weekStart`.
    private static func scheduledDates(
        weekStart: Date,
        scheduledDays: Set<Weekday>,
        calendar: Calendar
    ) -> [Date] {
        (0..<7).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return scheduledDays.contains(Weekday.from(date, calendar: calendar)) ? date : nil
        }
    }
}
