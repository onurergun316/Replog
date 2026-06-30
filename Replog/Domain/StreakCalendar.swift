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

    /// The seven cells (Sun…Sat) for the week containing `today`.
    static func weekStrip(doneDates: [Date], today: Date = Date(), calendar: Calendar = .current) -> [DayCell] {
        let startOfToday = calendar.startOfDay(for: today)
        // Find Sunday of the current week.
        let weekdayIndex = calendar.component(.weekday, from: startOfToday) - 1 // 0 = Sunday
        guard let sunday = calendar.date(byAdding: .day, value: -weekdayIndex, to: startOfToday) else { return [] }
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
