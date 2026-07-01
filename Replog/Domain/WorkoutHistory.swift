//
//  WorkoutHistory.swift
//  Replog
//
//  Reconstructs the list of completed workouts for the "Workouts" stat sheet. History
//  is stored per-exercise (`HistoryEntry`), so a "workout" is reconstructed as a
//  calendar day: the union of days the user marked complete (`doneDates`) and any day
//  with logged sets. Pure & testable — the view only resolves exercise names.
//

import Foundation

/// One completed training day and the exercises logged that day (heaviest first).
struct CompletedWorkoutDay: Identifiable {
    let day: Date
    let entries: [HistoryEntry]
    var id: Date { day }
    var exerciseCount: Int { entries.count }
}

enum WorkoutHistory {
    /// Completed days, newest first — the union of `doneDates` and days with history, so
    /// the list reflects every finished workout (not only those with saved sets).
    static func completedDays(doneDates: [Date], history: [HistoryEntry],
                              calendar: Calendar = .current) -> [CompletedWorkoutDay] {
        let byDay = Dictionary(grouping: history) { calendar.startOfDay(for: $0.date) }
        var days = Set(doneDates.map { calendar.startOfDay(for: $0) })
        days.formUnion(byDay.keys)
        return days.sorted(by: >).map { day in
            let entries = (byDay[day] ?? []).sorted {
                Formulas.e1rm(kg: $0.topW, reps: $0.topR) > Formulas.e1rm(kg: $1.topW, reps: $1.topR)
            }
            return CompletedWorkoutDay(day: day, entries: entries)
        }
    }
}
