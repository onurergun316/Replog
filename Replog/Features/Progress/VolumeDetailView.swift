//
//  VolumeDetailView.swift
//  Replog
//
//  Progress L2 — Volume: weekly tonnage bars over a chosen window, totals and
//  per-week averages, the rep-range mix (strength / hypertrophy / endurance), and a
//  week-by-week breakdown list.
//

import SwiftUI
import SwiftData
import Charts

struct VolumeDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @State private var window = RangeSelection()

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }


    /// Days from the athlete's first activity to today — the range control offers only
    /// windows that actually contain something.
    private var historySpanDays: Int? {
        guard let first = ProgressAnalytics.firstActivity(history: history, doneDates: [])
        else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
    }

    private var buckets: [WeekBucket] {
        ProgressAnalytics.trimmingLeadingEmptyWeeks(
            ProgressAnalytics.weekBuckets(history: history, weeks: window.weeks ?? 104, load: load))
    }

    private var mix: RepRangeMix {
        ProgressAnalytics.repRangeMix(history: history, days: window.days ?? 730, load: load)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Volume").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window, historySpanDays: historySpanDays)

                let trained = buckets.filter { $0.volumeKg > 0 }
                if trained.isEmpty {
                    ProgressEmptyCard(text: "No sets logged in this window yet.")
                } else {
                    summaryRow(trained: trained)
                    // The bucket follows the span. With four days of history a weekly
                    // chart is one bar — technically correct and completely shapeless —
                    // while the same data per session actually shows something.
                    if trained.count >= 2 { weeklyChart }
                    if !sessions.isEmpty { sessionSection }
                    loadSplitSection
                    repMixSection
                    weekList(trained: trained)
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryRow(trained: [WeekBucket]) -> some View {
        let total = trained.reduce(0.0) { $0 + $1.volumeKg }
        let groups = sessions
        return HStack(spacing: 12) {
            summaryTile(Formulas.formatWeight(kg: total, units: units, includeUnit: false),
                        "total \(units.label)")
            // An average over one week is just the total again — two tiles showing the
            // identical number reads as a bug. Below two trained weeks, report the
            // per-session average instead, which is a real second reading.
            if trained.count > 1 {
                summaryTile(Formulas.formatWeight(kg: total / Double(trained.count),
                                                  units: units, includeUnit: false),
                            "avg / week")
            } else if groups.count > 1 {
                summaryTile(Formulas.formatWeight(kg: total / Double(groups.count),
                                                  units: units, includeUnit: false),
                            "avg / session")
            } else {
                summaryTile("\(groups.count)", groups.count == 1 ? "session" : "sessions")
            }
            summaryTile("\(trained.reduce(0) { $0 + $1.sets })", "sets")
        }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .tabularNumbers().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .cardSurface()
    }

    private var weeklyChart: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                    y: .value("Volume", bucket.volumeKg))
                .foregroundStyle(Color.accent)
                .cornerRadius(3)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
        .padding(14)
        .cardSurface()
    }

    /// Sessions inside the window, oldest first — "total weight lifted per session",
    /// which per-exercise-per-day history could not answer before finishes were stamped.
    private var sessions: [ProgressAnalytics.SessionGroup] {
        let cutoff = window.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        } ?? .distantPast
        return ProgressAnalytics.sessions(history: history.filter { $0.date >= cutoff })
    }

    private var sessionSection: some View {
        let groups = sessions
        let density = ChartDensity.of(groups.count)
        let load = self.load
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Per Session")
            VStack(alignment: .leading, spacing: 8) {
                Chart(groups, id: \.id) { session in
                    BarMark(x: .value("Session", session.date, unit: .day),
                            y: .value("Volume", ProgressAnalytics.tonnage(of: session, load: load)))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(3)
                        // Two bars read better labelled than measured against an axis.
                        .annotation(position: .top) {
                            if density.labelsMarksDirectly {
                                Text(Formulas.formatWeight(
                                    kg: ProgressAnalytics.tonnage(of: session, load: load),
                                    units: units, includeUnit: false))
                                    .font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                            }
                        }
                }
                .chartYAxis { if density.showsAxis { AxisMarks(position: .leading) } }
                .frame(height: density.chartHeight)
                Text(groups.count == 1
                     ? "One session logged"
                     : "\(groups.count) sessions · heaviest \(Formulas.formatWeight(kg: groups.map { ProgressAnalytics.tonnage(of: $0, load: load) }.max() ?? 0, units: units))")
                    .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
            }
            .padding(14)
            .cardSurface()

            // Every session opens: a chart you cannot tap is a dead end, and this is the
            // step from "23,188 kg" to the individual workout that produced it.
            VStack(spacing: 0) {
                ForEach(Array(groups.reversed().enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider() }
                    NavigationLink(value: ProgressRoute.day(Calendar.current.startOfDay(for: session.date))) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.workoutName ?? "Workout")
                                    .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("\(session.date.formatted(.dateTime.weekday(.abbreviated).month().day())) · \(session.entries.count) exercises · \(session.setCount) sets")
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

    /// How much of the tonnage was plates and how much was the athlete's own body.
    @ViewBuilder
    private var loadSplitSection: some View {
        let split = ProgressAnalytics.loadSplit(history: history, days: window.days ?? 3650, load: load)
        let total = split.externalKg + split.bodyweightKg
        if total > 0, split.bodyweightKg > 0 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Where The Load Came From")
                VStack(alignment: .leading, spacing: 10) {
                    Chart {
                        BarMark(x: .value("kg", split.externalKg))
                            .foregroundStyle(ProgressPalette.ramp(0))
                        BarMark(x: .value("kg", split.bodyweightKg))
                            .foregroundStyle(ProgressPalette.ramp(2))
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                    .frame(height: 26)
                    .clipShape(Capsule())
                    splitRow("External load", split.externalKg, total, 0)
                    splitRow("Bodyweight", split.bodyweightKg, total, 2)
                }
                .padding(14)
                .cardSurface()
            }
        }
    }

    private func splitRow(_ label: String, _ value: Double, _ total: Double, _ ramp: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ProgressPalette.ramp(ramp)).frame(width: 8, height: 8)
            Text(label).font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
            Spacer()
            Text("\(Formulas.formatWeight(kg: value, units: units)) · \(Int((value / total * 100).rounded()))%")
                .font(.rounded(12, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
        }
    }

    private var repMixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Rep Ranges")
            VStack(alignment: .leading, spacing: 10) {
                if mix.total > 0 {
                    Chart {
                        BarMark(x: .value("Sets", mix.strength))
                            .foregroundStyle(ProgressPalette.ramp(0))
                        BarMark(x: .value("Sets", mix.hypertrophy))
                            .foregroundStyle(ProgressPalette.ramp(1))
                        BarMark(x: .value("Sets", mix.endurance))
                            .foregroundStyle(ProgressPalette.ramp(2))
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 26)
                    .clipShape(Capsule())
                    legendRow("1–5 reps · strength", mix.strength, 0)
                    legendRow("6–12 reps · hypertrophy", mix.hypertrophy, 1)
                    legendRow("13+ reps · endurance", mix.endurance, 2)
                }
            }
            .padding(14)
            .cardSurface()
        }
    }

    private func legendRow(_ label: String, _ count: Int, _ rampIndex: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ProgressPalette.ramp(rampIndex)).frame(width: 8, height: 8)
            Text(label).font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
            Spacer()
            Text("\(count) sets").font(.rounded(12, .heavy)).foregroundStyle(Color.textPrimary)
                .tabularNumbers()
        }
    }

    private func weekList(trained: [WeekBucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Week by Week")
            VStack(spacing: 0) {
                ForEach(Array(trained.reversed().enumerated()), id: \.element.id) { index, week in
                    if index > 0 { Divider() }
                    NavigationLink(value: ProgressRoute.week(week.weekStart)) {
                        HStack {
                            Text(week.weekStart, format: .dateTime.month(.abbreviated).day())
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                                .frame(width: 64, alignment: .leading)
                            Text("\(week.workouts)× · \(week.sets) sets")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                            Spacer()
                            Text(Formulas.formatWeight(kg: week.volumeKg, units: units))
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.text2).tabularNumbers()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }
}
