//
//  StreakCalendar.swift
//  Replog
//
//  Week strip + streak logic for the Today screen. Only days actually completed
//  are colored; the streak is the run of consecutive days ending today.
//

import Foundation

/// One cell in the Today week strip (Sun…Sat).
struct DayCell: Equatable, Identifiable, Sendable {
    var date: Date
    var weekday: Weekday
    var isToday: Bool
    var isCompleted: Bool
    var id: Weekday { weekday }
}

enum StreakCalendar {

    /// The Sunday that starts the week `weekOffset` weeks from the one containing `today`.
    /// Negative offsets go back, positive forward.
    static func weekStart(offset weekOffset: Int = 0, today: Date = Date(),
                          calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: today)
        let weekdayIndex = calendar.component(.weekday, from: startOfToday) - 1 // 0 = Sunday
        guard let sunday = calendar.date(byAdding: .day, value: -weekdayIndex, to: startOfToday) else { return nil }
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: sunday)
    }

    /// The seven cells (Sun…Sat) for the week `weekOffset` weeks from the one containing
    /// `today`. Offset 0 is the current week, -1 last week, +1 next week.
    static func weekStrip(doneDates: [Date], weekOffset: Int = 0,
                          today: Date = Date(), calendar: Calendar = .current) -> [DayCell] {
        guard let sunday = weekStart(offset: weekOffset, today: today, calendar: calendar) else { return [] }
        let startOfToday = calendar.startOfDay(for: today)
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: sunday) else { return nil }
            return DayCell(
                date: date,
                weekday: Weekday.from(date, calendar: calendar),
                isToday: calendar.isDate(date, inSameDayAs: startOfToday),
                isCompleted: doneDays.contains(date)
            )
        }
    }

    /// How far the week strip may be swiped, in weeks relative to the current one.
    ///
    /// Back as far as there is training to look at, capped so the pager never becomes an
    /// unbounded scroll, and always at least one week either side so the strip is visibly
    /// swipeable from day one. Forward is deliberately short: beyond next week there is
    /// nothing to see but the same repeating schedule.
    static func weekWindow(doneDates: [Date], today: Date = Date(), calendar: Calendar = .current,
                           maxWeeksBack: Int = 52, weeksForward: Int = 1) -> ClosedRange<Int> {
        let forward = max(0, weeksForward)
        guard let currentSunday = weekStart(today: today, calendar: calendar),
              let earliestDone = doneDates.min(),
              // Snap to that date's own Sunday first: measuring from a Monday truncates
              // the part-week and reports one week fewer than the strip can actually show.
              let earliestSunday = weekStart(today: earliestDone, calendar: calendar) else {
            return -1...forward
        }
        let weeks = calendar.dateComponents([.weekOfYear], from: earliestSunday, to: currentSunday).weekOfYear ?? 0
        // At least one week back, never more than the cap.
        let back = min(max(1, weeks), max(1, maxWeeksBack))
        return (-back)...forward
    }

    /// A short label for a week page: "This week", "Last week", "Next week", or a date range.
    static func weekLabel(offset: Int, today: Date = Date(), calendar: Calendar = .current) -> String {
        switch offset {
        case 0:  return "This week"
        case -1: return "Last week"
        case 1:  return "Next week"
        default: break
        }
        guard let start = weekStart(offset: offset, today: today, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "" }
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    /// Records a completion for `day`, returning the de-duplicated date list (one per calendar day).
    static func recordingCompletion(_ day: Date, into doneDates: [Date], calendar: Calendar = .current) -> [Date] {
        let target = calendar.startOfDay(for: day)
        var days = Set(doneDates.map { calendar.startOfDay(for: $0) })
        days.insert(target)
        return days.sorted()
    }

    /// The streak: number of consecutive calendar days ending at `today` that are completed.
    /// If today isn't completed, counts the run ending yesterday (so a streak survives until the day ends).
    static func streak(doneDates: [Date], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        guard !doneDays.isEmpty else { return 0 }
        let startOfToday = calendar.startOfDay(for: today)

        // Anchor: today if done, else yesterday (grace period for the current day).
        var anchor = startOfToday
        if !doneDays.contains(anchor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
                  doneDays.contains(yesterday) else { return 0 }
            anchor = yesterday
        }

        var count = 0
        var cursor = anchor
        while doneDays.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }
}
