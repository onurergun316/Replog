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
            ProgressAnalytics.weekBuckets(history: history, weeks: window.weeks ?? RangeSelection.allTimeWeeks, load: load))
    }

    private var mix: RepRangeMix {
        ProgressAnalytics.repRangeMix(history: history, days: window.days ?? RangeSelection.allTimeDays, load: load)
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

    /// Every tile opens. A headline you can read but cannot question is where the screen
    /// used to stop — "23,188 kg" is only useful next to which lifts produced it.
    private func summaryRow(trained: [WeekBucket]) -> some View {
        let total = trained.reduce(0.0) { $0 + $1.volumeKg }
        let groups = sessions
        return HStack(spacing: 12) {
            StatTile(value: Formulas.formatWeight(kg: total, units: units, includeUnit: false),
                     label: "total \(units.label)",
                     route: .volumeStat(.total, days: window.days))
            // An average over one week is just the total again — two tiles showing the
            // identical number reads as a bug. Below two trained weeks, report the
            // per-session average instead, which is a real second reading.
            if trained.count > 1 {
                StatTile(value: Formulas.formatWeight(kg: total / Double(trained.count),
                                                      units: units, includeUnit: false),
                         label: "avg / week",
                         route: .volumeStat(.average, days: window.days))
            } else if groups.count > 1 {
                StatTile(value: Formulas.formatWeight(kg: total / Double(groups.count),
                                                      units: units, includeUnit: false),
                         label: "avg / session",
                         route: .volumeStat(.average, days: window.days))
            } else {
                StatTile(value: "\(groups.count)",
                         label: groups.count == 1 ? "session" : "sessions",
                         route: .volumeStat(.average, days: window.days))
            }
            StatTile(value: "\(trained.reduce(0) { $0 + $1.sets })", label: "sets",
                     route: .volumeStat(.sets, days: window.days))
        }
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
        let cutoff = ProgressAnalytics.cutoff(days: window.resolvedDays)
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
                                Text(session.title())
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
        let split = ProgressAnalytics.loadSplit(history: history, days: window.days ?? RangeSelection.allTimeDays, load: load)
        let total = split.externalKg + split.bodyweightKg
        if total > 0, split.bodyweightKg > 0 {
            // The whole card opens: a split raises "which movements, and when", and the
            // percentages here cannot answer either.
            SectionLink(title: "Where The Load Came From",
                        route: .loadSplit(days: window.days)) {
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
                    LegendRow(label: "External load",
                              value: splitValue(split.externalKg, total), ramp: 0)
                    LegendRow(label: "Bodyweight",
                              value: splitValue(split.bodyweightKg, total), ramp: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .cardSurface()
            }
        }
    }

    private func splitValue(_ value: Double, _ total: Double) -> String {
        let percent = total > 0 ? Int((value / total * 100).rounded()) : 0
        return "\(Formulas.formatWeight(kg: value, units: units)) · \(percent)%"
    }

    @ViewBuilder
    private var repMixSection: some View {
        if mix.total > 0 {
            // Opens onto which movements you train in which range — the thing you'd
            // actually change, which the shape alone never says.
            SectionLink(title: "Rep Ranges", route: .repRanges(days: window.days)) {
                RepRangeBar(mix: mix)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            }
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
