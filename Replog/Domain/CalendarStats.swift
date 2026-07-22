//
//  CalendarStats.swift
//  Replog
//
//  Statistics for the Calendar tab: which days are "done", what one day contains, and
//  totals + per-training-day averages over any selected range of days — the same math
//  the weekly reports use, applied to an arbitrary selection. Days are binary: several
//  finishes in one day still count one training day. Pure and fully testable.
//

import Foundation

/// Totals and averages for a selected set of calendar days.
struct RangeSummary: Equatable {
    var selectedDays: Int = 0
    /// Selected days on which a workout was completed (or sets were logged).
    var trainingDays: Int = 0
    var totalSets: Int = 0
    var totalReps: Int = 0
    var totalVolumeKg: Double = 0
    var distinctExercises: Int = 0
    var bestLift: BestLift?

    /// Per-training-day averages (zero when nothing was trained).
    var avgSetsPerTrainingDay: Double {
        trainingDays == 0 ? 0 : Double(totalSets) / Double(trainingDays)
    }
    var avgVolumePerTrainingDay: Double {
        trainingDays == 0 ? 0 : totalVolumeKg / Double(trainingDays)
    }
}

/// The heaviest lift (by estimated 1RM) inside a range.
struct BestLift: Equatable {
    var exId: String
    var weightKg: Double
    var reps: Int
    var e1rm: Int
}

/// One day's aggregated training numbers — precomputed once so the calendar UI never
/// re-decodes history mid-drag.
struct DayTotals: Equatable {
    var sets = 0
    var reps = 0
    var volumeKg = 0.0
}

enum CalendarStats {

    /// Per-day totals over the whole history — decode each entry's sets exactly once.
    static func dayTotals(history: [HistoryEntry],
                          calendar: Calendar = .current) -> [Date: DayTotals] {
        var totals: [Date: DayTotals] = [:]
        for entry in history {
            let day = calendar.startOfDay(for: entry.date)
            var t = totals[day, default: DayTotals()]
            for set in entry.sets {
                t.sets += 1
                t.reps += set.r
                t.volumeKg += set.w * Double(set.r)
            }
            totals[day] = t
        }
        return totals
    }

    /// Every day (start-of-day) with a completed workout or logged sets — the union of
    /// the completion calendar and history days, matching `WorkoutHistory.completedDays`.
    static func doneDays(doneDates: [Date], history: [HistoryEntry],
                         calendar: Calendar = .current) -> Set<Date> {
        var days = Set(doneDates.map { calendar.startOfDay(for: $0) })
        days.formUnion(history.map { calendar.startOfDay(for: $0.date) })
        return days
    }

    /// One day's history entries, heaviest first (the day-detail list).
    static func entries(on day: Date, history: [HistoryEntry],
                        calendar: Calendar = .current) -> [HistoryEntry] {
        history
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.e1rm > $1.e1rm }
    }

    /// Totals + averages across `selection`. Days are binary training days; totals sum
    /// every logged set on the selected days.
    static func summary(selection: Set<Date>, doneDates: [Date], history: [HistoryEntry],
                        calendar: Calendar = .current) -> RangeSummary {
        let selectedDays = Set(selection.map { calendar.startOfDay(for: $0) })
        let done = doneDays(doneDates: doneDates, history: history, calendar: calendar)

        var result = RangeSummary()
        result.selectedDays = selectedDays.count
        result.trainingDays = selectedDays.intersection(done).count

        let entries = history.filter { entry in
            selectedDays.contains(calendar.startOfDay(for: entry.date))
        }
        var exIds = Set<String>()
        for entry in entries {
            exIds.insert(entry.exId)
            for set in entry.sets {
                result.totalSets += 1
                result.totalReps += set.r
                result.totalVolumeKg += set.w * Double(set.r)
            }
            if entry.e1rm > (result.bestLift?.e1rm ?? 0) {
                result.bestLift = BestLift(exId: entry.exId, weightKg: entry.topW,
                                           reps: entry.topR, e1rm: entry.e1rm)
            }
        }
        result.distinctExercises = exIds.count
        return result
    }

    /// The month-footer line's numbers from precomputed caches: training days + volume
    /// within the month of `month`. Month membership uses `toGranularity: .month` —
    /// `DateInterval.contains` is end-INCLUSIVE and a month interval ends at the next
    /// month's first instant, which is exactly where a start-of-day done mark for the
    /// 1st lands, double-counting it.
    static func monthTotals(month: Date, doneDays: Set<Date>, dayTotals: [Date: DayTotals],
                            calendar: Calendar = .current) -> (workouts: Int, volumeKg: Double) {
        let workouts = doneDays
            .filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count
        let volume = dayTotals.reduce(0.0) { sum, item in
            calendar.isDate(item.key, equalTo: month, toGranularity: .month)
                ? sum + item.value.volumeKg : sum
        }
        return (workouts, volume)
    }

    /// Convenience over raw data (tests, one-shot callers) — derives both caches.
    static func monthTotals(month: Date, doneDates: [Date], history: [HistoryEntry],
                            calendar: Calendar = .current) -> (workouts: Int, volumeKg: Double) {
        monthTotals(month: month,
                    doneDays: doneDays(doneDates: doneDates, history: history, calendar: calendar),
                    dayTotals: dayTotals(history: history, calendar: calendar),
                    calendar: calendar)
    }
}
