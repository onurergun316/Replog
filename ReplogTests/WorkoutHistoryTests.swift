//
//  WorkoutHistoryTests.swift
//  ReplogTests
//
//  Reconstructing the "Workouts" list from doneDates + per-exercise history.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct WorkoutHistoryTests {
    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
    }

    private func entry(_ exId: String, day offset: Int, w: Double = 60, r: Int = 8) -> HistoryEntry {
        HistoryEntry(exId: exId, date: day(offset), topW: w, topR: r,
                     e1rm: Formulas.e1rmRounded(kg: w, reps: r), sets: [RecordedSet(w: w, r: r)])
    }

    @Test func unionsDoneDatesAndHistoryDays() {
        // doneDate today (no history) + history two days ago → two distinct days.
        let days = WorkoutHistory.completedDays(
            doneDates: [day(0)],
            history: [entry("Bench", day: -2)],
            calendar: cal)
        #expect(days.count == 2)
        #expect(days[0].day == cal.startOfDay(for: day(0)))   // newest first
        #expect(days[1].day == cal.startOfDay(for: day(-2)))
    }

    @Test func sameDayEntriesCollapseIntoOneDay() {
        let days = WorkoutHistory.completedDays(
            doneDates: [],
            history: [entry("Bench", day: -1), entry("Squat", day: -1), entry("Row", day: -1)],
            calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].exerciseCount == 3)
    }

    @Test func doneDateWithoutHistoryHasNoEntries() {
        let days = WorkoutHistory.completedDays(doneDates: [day(0)], history: [], calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].entries.isEmpty)
        #expect(days[0].exerciseCount == 0)
    }

    @Test func entriesAreSortedByEstimated1RMDescending() {
        let light = entry("Light", day: -1, w: 40, r: 8)
        let heavy = entry("Heavy", day: -1, w: 100, r: 8)
        let days = WorkoutHistory.completedDays(doneDates: [], history: [light, heavy], calendar: cal)
        #expect(days[0].entries.first?.exId == "Heavy")   // heaviest first
    }

    @Test func emptyInputsProduceNoDays() {
        #expect(WorkoutHistory.completedDays(doneDates: [], history: [], calendar: cal).isEmpty)
    }
}
