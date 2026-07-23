//
//  CalendarMath.swift
//  Replog
//
//  Date math for the Calendar tab's month grid. Pages are a fixed 42 cells (6 rows × 7
//  Sunday-first columns) so month heights never jump; leading/trailing cells belong toyou ha
//  the adjacent months. Sunday-first matches the Today week strip and StreakEngine's
//  weeks regardless of locale. Pure and fully testable.
//

import Foundation

enum CalendarMath {

    /// The app's grid calendar: the user's calendar pinned to Sunday-first weeks, so
    /// columns line up with `WeekStripView` and `StreakEngine.startOfWeek`.
    static func gridCalendar(_ base: Calendar = .current) -> Calendar {
        var c = base
        c.firstWeekday = 1
        return c
    }

    /// The 42 dates (start-of-day) of the month page containing `date`: the month's own
    /// days plus enough leading/trailing adjacent-month days to fill 6 whole weeks.
    static func monthCells(containing date: Date, calendar: Calendar) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)
        else { return [] }
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstWeek.start)
        }
    }

    /// Whether `day` falls inside the calendar month containing `month`.
    static func isInMonth(_ day: Date, of month: Date, calendar: Calendar) -> Bool {
        calendar.isDate(day, equalTo: month, toGranularity: .month)
    }

    /// The first moment of the month `offset` months away from the one containing `date`.
    static func month(_ offset: Int, from date: Date, calendar: Calendar) -> Date? {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return nil }
        return calendar.date(byAdding: .month, value: offset, to: start)
    }
}
