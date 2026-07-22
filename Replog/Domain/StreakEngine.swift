//
//  StreakEngine.swift
//  Replog
//
//  Schedule-aware streaks. Unlike a Duolingo daily streak, these are driven by the
//  user's *plan schedule* (which weekdays have a workout):
//
//   • Workout streak — consecutive scheduled workouts completed. A scheduled weekday
//     that ends without its workout done resets it to 0. Today's scheduled workout,
//     while still undone, does not break it (in-progress grace).
//
//   • Week streak — consecutive "perfect weeks" (every scheduled workout that week
//     completed). Because a missed workout breaks the workout streak, it also breaks
//     the week streak ("grouped inside"): the workout streak counts sessions, the week
//     streak counts whole weeks, and a single miss resets both.
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

    /// Consecutive scheduled workouts completed, counting back from `today`.
    /// Stops at the first *past* scheduled weekday with no completion. A scheduled
    /// workout that is still due today (undone) is skipped, not counted as a miss.
    static func workoutStreak(
        scheduledDays: Set<Weekday>,
        doneDates: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !scheduledDays.isEmpty else { return 0 }
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        guard !doneDays.isEmpty else { return 0 }

        let startOfToday = calendar.startOfDay(for: today)
        var cursor = startOfToday
        var count = 0
        // Safety bound: never walk more than ~2 years of days.
        for _ in 0..<732 {
            let weekday = Weekday.from(cursor, calendar: calendar)
            if scheduledDays.contains(weekday) {
                if doneDays.contains(cursor) {
                    count += 1
                } else if cursor != startOfToday {
                    // A past scheduled workout was missed → streak ends here.
                    break
                }
                // else: today's scheduled workout is still due — grace, don't break.
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            // Once we're older than every completion, the next scheduled day is a miss.
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
