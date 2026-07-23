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
    @State private var window: RangeWindow = .twelveWeeks

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

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
                RangePicker(selection: $window)

                let trained = buckets.filter { $0.volumeKg > 0 }
                if trained.isEmpty {
                    ProgressEmptyCard(text: "No sets logged in this window yet.")
                } else {
                    summaryRow(trained: trained)
                    weeklyChart
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
        let avg = total / Double(trained.count)
        return HStack(spacing: 12) {
            summaryTile(Formulas.formatWeight(kg: total, units: units, includeUnit: false),
                        "total \(units.label)")
            summaryTile(Formulas.formatWeight(kg: avg, units: units, includeUnit: false),
                        "avg / trained week")
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
                    HStack {
                        Text(week.weekStart, format: .dateTime.month(.abbreviated).day())
                            .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                            .frame(width: 64, alignment: .leading)
                        Text("\(week.workouts)× · \(week.sets) sets")
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                        Spacer()
                        Text(Formulas.formatWeight(kg: week.volumeKg, units: units))
                            .font(.rounded(13, .heavy)).foregroundStyle(Color.text2).tabularNumbers()
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }
}
