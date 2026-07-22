//
//  StatDetailSheet.swift
//  Replog
//
//  Bottom sheets opened from the Today/Profile stat cards, showing the logs and
//  history behind each number. Dismissed by swiping down (no Done button).
//

import SwiftUI

/// Which stat a detail sheet is describing.
enum StatKind: String, Identifiable {
    case workoutStreak, weekStreak, thisWeek, workouts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .workoutStreak: return "Workout Streak"
        case .weekStreak:    return "Week Streak"
        case .thisWeek:      return "This Week"
        case .workouts:      return "Workouts"
        }
    }

    var systemImage: String {
        switch self {
        case .workoutStreak: return "flame.fill"
        case .weekStreak:    return "calendar.badge.checkmark"
        case .thisWeek:      return "calendar"
        case .workouts:      return "checkmark.seal.fill"
        }
    }
}

struct StatDetailSheet: View {
    let kind: StatKind
    let doneDates: [Date]
    let history: [HistoryEntry]
    let catalog: ExerciseCatalog
    /// Number of workouts scheduled per week across all plans.
    let scheduledCount: Int
    let workoutStreakValue: Int
    let weekStreakValue: Int
    let totalWorkouts: Int

    @State private var expandedDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch kind {
                    case .workoutStreak: workoutStreakContent
                    case .weekStreak:    weekStreakContent
                    case .thisWeek:      thisWeekContent
                    case .workouts:      workoutsContent
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Workout streak — consecutive completed days

    private var workoutStreakContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(value: "\(workoutStreakValue)",
                    caption: workoutStreakValue == 1 ? "training day in a row" : "training days in a row")
            Text("Complete each scheduled workout to keep the streak alive. A missed scheduled day resets it.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
            if completedDays.isEmpty {
                emptyState("No workouts yet", "Finish a scheduled workout to start your streak.")
            } else {
                ForEach(completedDays.prefix(14)) { day in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
                        Text(day.day, format: .dateTime.weekday(.wide).month().day())
                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                        Spacer()
                        if day.exerciseCount > 0 {
                            Text("\(day.exerciseCount) ex").font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                        }
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
    }

    // MARK: Week streak — recent weeks with done/scheduled counts

    private var weekStreakContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(value: "\(weekStreakValue)",
                    caption: weekStreakValue == 1 ? "perfect week in a row" : "perfect weeks in a row")
            Text("A week is perfect when you complete every scheduled workout. Missing one resets the streak.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
            if recentWeeks.isEmpty {
                emptyState("No weeks logged yet", "Finish a scheduled workout to start your streak.")
            } else {
                ForEach(recentWeeks) { week in
                    HStack {
                        Image(systemName: week.isPerfect ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(week.isPerfect ? Color.up : Color.text3)
                        Text(week.label).font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(week.done)/\(max(scheduledCount, week.done)) done")
                            .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
    }

    // MARK: This week — completed days

    private var thisWeekContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(value: "\(thisWeekDates.count)",
                    caption: thisWeekDates.count == 1 ? "workout this week" : "workouts this week")
            if thisWeekDates.isEmpty {
                emptyState("Nothing logged this week", "Your completed workouts this week will show here.")
            } else {
                ForEach(thisWeekDates, id: \.self) { date in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
                        Text(date, format: .dateTime.weekday(.wide).month().day())
                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
        }
    }

    // MARK: Workouts — one expandable row per completed day

    private var workoutsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary(value: "\(totalWorkouts)",
                    caption: totalWorkouts == 1 ? "workout completed" : "workouts completed")
            if completedDays.isEmpty {
                emptyState("No history yet", "Finish a workout to build your training log.")
            } else {
                ForEach(completedDays) { day in
                    WorkoutDayRow(day: day, catalog: catalog,
                                  isExpanded: expandedDay == day.day) {
                        withAnimation(.snappy) {
                            expandedDay = expandedDay == day.day ? nil : day.day
                        }
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: Shared bits

    private func summary(value: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(.bigMetric).foregroundStyle(Color.textPrimary).tabularNumbers()
            Text(caption).font(.rounded(14, .bold)).foregroundStyle(Color.text2)
        }
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: kind.systemImage).font(.system(size: 26)).foregroundStyle(Color.text3)
            Text(title).font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text(subtitle).font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    // MARK: Derived data

    private var calendar: Calendar { .current }

    private var completedDays: [CompletedWorkoutDay] {
        WorkoutHistory.completedDays(doneDates: doneDates, history: history, calendar: calendar)
    }

    private var thisWeekDates: [Date] {
        doneDates
            .filter { calendar.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }
            .sorted(by: >)
    }

    private struct WeekRow: Identifiable {
        let id = UUID()
        let label: String
        let done: Int
        var isPerfect: Bool
    }

    /// The last 8 weeks (most recent first) with completed-workout counts.
    private var recentWeeks: [WeekRow] {
        guard !doneDates.isEmpty else { return [] }
        let today = Date()
        return (0..<8).compactMap { offset -> WeekRow? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset,
                                                to: calendar.startOfWeek(for: today)) else { return nil }
            let done = doneDates.filter { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) }.count
            guard done > 0 || offset == 0 else { return nil }
            let label = offset == 0 ? "This week" : (offset == 1 ? "Last week" : "\(offset) weeks ago")
            return WeekRow(label: label, done: done, isPerfect: scheduledCount > 0 && done >= scheduledCount)
        }
    }
}

/// A tappable "completed workout day" row that expands to show its exercises.
private struct WorkoutDayRow: View {
    let day: CompletedWorkoutDay
    let catalog: ExerciseCatalog
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.day, format: .dateTime.weekday(.wide).month().day().year())
                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                        Text(summaryLine)
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Spacer(minLength: 8)
                    if day.exerciseCount > 0 {
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.text3)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(day.exerciseCount == 0)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(day.entries) { entry in
                        HStack {
                            Text(catalog.exercise(id: entry.exId)?.name ?? entry.exId)
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                            Spacer()
                            Text("\(Int(entry.topW))kg × \(entry.topR)")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2).tabularNumbers()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 10)
    }

    private var summaryLine: String {
        guard day.exerciseCount > 0 else { return "Workout completed" }
        let names = day.entries.compactMap { catalog.exercise(id: $0.exId)?.name }
        return names.prefix(3).joined(separator: " · ")
            + (names.count > 3 ? " +\(names.count - 3)" : "")
    }
}

private extension Calendar {
    /// The start of the week containing `date`, respecting the calendar's first weekday.
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
