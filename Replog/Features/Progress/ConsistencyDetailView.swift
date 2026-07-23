//
//  ConsistencyDetailView.swift
//  Replog
//
//  Progress L2 — Consistency: schedule adherence per week over a chosen window, the
//  current streaks, and a week-by-week list of scheduled vs done.
//

import SwiftUI
import SwiftData
import Charts

struct ConsistencyDetailView: View {
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query private var profiles: [UserProfile]
    @State private var window: RangeWindow = .twelveWeeks

    /// Read-only: the singletons are bootstrapped in `ReplogApp.init`, so a view body
    /// never needs to create one — and must not, mid-render.
    private var doneDates: [Date] { profiles.first?.doneDates ?? [] }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }

    private var weeks: [AdherenceWeek] {
        ProgressAnalytics.adherence(scheduledDays: scheduledDays,
                                    doneDates: doneDates,
                                    weeks: window.weeks ?? 104)
    }

    private var streak: Int {
        StreakEngine.workoutStreak(scheduledDays: scheduledDays, doneDates: doneDates)
    }
    private var weekStreak: Int {
        StreakEngine.weekStreak(scheduledDays: scheduledDays, doneDates: doneDates)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Consistency").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window)

                let active = weeks.filter { $0.scheduled > 0 }
                if active.isEmpty {
                    ProgressEmptyCard(text: "No scheduled weeks in this window — add workouts to a plan to track adherence.")
                } else {
                    summaryRow(active: active)
                    adherenceChart
                    weekList(active: active)
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryRow(active: [AdherenceWeek]) -> some View {
        let scheduled = active.reduce(0) { $0 + $1.scheduled }
        let done = active.reduce(0) { $0 + $1.done }
        let percent = scheduled == 0 ? 0 : Int((Double(done) / Double(scheduled) * 100).rounded())
        return HStack(spacing: 12) {
            tile("\(percent)%", "adherence")
            tile("\(streak)", "day streak")
            tile("\(weekStreak)", "week streak")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(18, .black)).foregroundStyle(Color.textPrimary).tabularNumbers()
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .cardSurface()
    }

    private var adherenceChart: some View {
        Chart(weeks) { week in
            BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Scheduled", week.scheduled))
                .foregroundStyle(Color.track)
                .cornerRadius(3)
            BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Done", week.done))
                .foregroundStyle(Color.accent)
                .cornerRadius(3)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 180)
        .padding(14)
        .cardSurface()
    }

    private func weekList(active: [AdherenceWeek]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Week by Week")
            VStack(spacing: 0) {
                ForEach(Array(active.reversed().enumerated()), id: \.element.id) { index, week in
                    if index > 0 { Divider() }
                    HStack {
                        Text(week.weekStart, format: .dateTime.month(.abbreviated).day())
                            .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                            .frame(width: 64, alignment: .leading)
                        Spacer()
                        Text("\(week.done)/\(week.scheduled) scheduled days")
                            .font(.rounded(12, .semibold))
                            .foregroundStyle(week.done >= week.scheduled ? Color.up : Color.text2)
                        if week.done >= week.scheduled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(Color.up)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }
}
