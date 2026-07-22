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

enum CalendarStats {

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

    /// The month-footer line's numbers: training days + volume within the month of `month`.
    static func monthTotals(month: Date, doneDates: [Date], history: [HistoryEntry],
                            calendar: Calendar = .current) -> (workouts: Int, volumeKg: Double) {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return (0, 0) }
        let done = doneDays(doneDates: doneDates, history: history, calendar: calendar)
        let workouts = done.filter { interval.contains($0) }.count
        let volume = history
            .filter { interval.contains($0.date) }
            .reduce(0.0) { sum, entry in
                sum + entry.sets.reduce(0) { $0 + $1.w * Double($1.r) }
            }
        return (workouts, volume)
    }
}
