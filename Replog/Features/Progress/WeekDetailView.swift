//
//  WeekDetailView.swift
//  Replog
//
//  Progress L3 — one week. Totals for the week, a Sunday-first bar per day, and the
//  sessions inside it; each day pushes on to its own log (L4).
//
//  Deliberately a static report rather than a pre-selected Calendar: the Calendar keeps
//  its browsing gestures and stays the place you explore, while this is the place a
//  number on the Volume chart explains itself. Both render through `CalendarStats`, so
//  there is one implementation of the arithmetic.
//

import SwiftUI
import SwiftData
import Charts

struct WeekDetailView: View {
    let weekStart: Date

    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    private var cal: Calendar { .current }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: weekStart)) }
    }

    private var inWeek: [HistoryEntry] {
        guard let end = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: weekStart))
        else { return [] }
        return history.filter { $0.date >= cal.startOfDay(for: weekStart) && $0.date < end }
    }

    private var dayTotals: [Date: DayTotals] {
        CalendarStats.dayTotals(history: inWeek, load: load, calendar: cal)
    }

    private var sessions: [ProgressAnalytics.SessionGroup] {
        ProgressAnalytics.sessions(history: inWeek).reversed()
    }

    private var totalVolume: Double {
        inWeek.reduce(0.0) { $0 + load.volumeKg($1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week of").eyebrow()
                    Text(weekStart, format: .dateTime.month(.wide).day())
                        .font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if inWeek.isEmpty {
                    ProgressEmptyCard(text: "Nothing logged this week.")
                } else {
                    summaryRow
                    dayChart
                    sessionList
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryRow: some View {
        let totals = dayTotals.values
        return HStack(spacing: 12) {
            tile(Formulas.formatWeight(kg: totalVolume, units: units, includeUnit: false),
                 "total \(units.label)")
            tile("\(totals.reduce(0) { $0 + $1.sets })", "sets")
            tile("\(dayTotals.count)", dayTotals.count == 1 ? "training day" : "training days")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .tabularNumbers().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .cardSurface()
    }

    /// Seven bars, Sunday first — rest days render as an empty slot rather than vanishing,
    /// so the shape of the week is readable at a glance.
    private var dayChart: some View {
        Chart(days, id: \.self) { day in
            let volume = dayTotals[cal.startOfDay(for: day)]?.volumeKg ?? 0
            BarMark(x: .value("Day", day, unit: .day),
                    y: .value("Volume", volume))
                .foregroundStyle(volume > 0 ? Color.accent : Color.track)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: days) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 160)
        .padding(14)
        .cardSurface()
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: sessions.count == 1 ? "Session" : "Sessions")
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider() }
                    NavigationLink(value: ProgressRoute.day(cal.startOfDay(for: session.date))) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.workoutName ?? "Workout")
                                    .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text(sessionCaption(session))
                                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Formulas.formatWeight(
                                kg: ProgressAnalytics.tonnage(of: session, load: load), units: units))
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                                .tabularNumbers()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }

    private func sessionCaption(_ session: ProgressAnalytics.SessionGroup) -> String {
        var parts = [session.date.formatted(.dateTime.weekday(.abbreviated).day())]
        parts.append("\(session.entries.count) exercises · \(session.setCount) sets")
        if let seconds = session.durationSeconds, seconds >= 60 {
            parts.append("\(seconds / 60) min")
        }
        return parts.joined(separator: " · ")
    }
}
