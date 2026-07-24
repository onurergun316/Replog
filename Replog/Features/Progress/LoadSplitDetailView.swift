//
//  LoadSplitDetailView.swift
//  Replog
//
//  Progress L3 — where the load came from.
//
//  The Volume screen states the split as one capsule: 71% external, 29% bodyweight. The
//  obvious next question is which movements each half is, and when they happened, and
//  that is the whole of this screen: the split per training day, then every exercise on
//  each side of it with the days it was trained.
//
//  It also explains itself. Bodyweight crediting is the one number in the app a user
//  cannot reconstruct from what they typed — they logged "0 kg × 12" and the app charged
//  it as several hundred kilograms — so the definition is on the screen, not in a doc.
//

import SwiftUI
import SwiftData
import Charts

struct LoadSplitDetailView: View {
    /// The window the split was read in — `nil` is all time.
    let days: Int?

    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }
    private var windowDays: Int { days ?? RangeSelection.allTimeDays }

    private var contributions: [ExerciseContribution] {
        ProgressAnalytics.exerciseContributions(history: history, days: windowDays, load: load)
    }

    private var daily: [(day: Date, externalKg: Double, bodyweightKg: Double)] {
        ProgressAnalytics.dailyLoadSplit(history: history, days: windowDays, load: load)
    }

    // Every reader below used to touch `contributions`, and each touch re-walks the whole
    // history JSON-decoding every entry's sets. One derivation per render, threaded down.
    var body: some View {
        let rows = contributions
        let external = rows.reduce(0) { $0 + $1.externalKg }
        let bodyweight = rows.reduce(0) { $0 + $1.bodyweightKg }
        let perDay = daily
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RangeSelection.label(days: days)).eyebrow()
                    Text("Where The Load Came From")
                        .font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if external + bodyweight <= 0 {
                    ProgressEmptyCard(text: "No load logged in this window yet.")
                } else {
                    splitCard(external: external, bodyweight: bodyweight)
                    if perDay.count >= 2 { dailyChart(perDay) }
                    exerciseSection(title: "External Load",
                                    rows: rows.filter { $0.externalKg > 0 }
                                        .sorted { $0.externalKg > $1.externalKg },
                                    value: { $0.externalKg })
                    exerciseSection(title: "Bodyweight Movements",
                                    rows: rows.filter { $0.bodyweightKg > 0 }
                                        .sorted { $0.bodyweightKg > $1.bodyweightKg },
                                    value: { $0.bodyweightKg })
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: The split itself

    private func splitCard(external: Double, bodyweight: Double) -> some View {
        let total = external + bodyweight
        return VStack(alignment: .leading, spacing: 12) {
            Chart {
                BarMark(x: .value("kg", external))
                    .foregroundStyle(ProgressPalette.ramp(0))
                BarMark(x: .value("kg", bodyweight))
                    .foregroundStyle(ProgressPalette.ramp(2))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .frame(height: 26)
            .clipShape(Capsule())
            LegendRow(label: "External load", value: legend(external, of: total), ramp: 0)
            LegendRow(label: "Bodyweight", value: legend(bodyweight, of: total), ramp: 2)
            Divider()
            Text("Weight on the bar is what you typed. Bodyweight movements are credited at the share of your bodyweight the movement actually lifts — which is why a set logged as 0 kg still counts.")
                .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .cardSurface()
    }

    private func legend(_ value: Double, of total: Double) -> String {
        let percent = total > 0 ? Int((value / total * 100).rounded()) : 0
        return "\(Formulas.formatWeight(kg: value, units: units)) · \(percent)%"
    }

    /// Stacked by day, so the answer to "when was this bodyweight work" is the chart
    /// rather than a paragraph.
    private func dailyChart(
        _ daily: [(day: Date, externalKg: Double, bodyweightKg: Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Day By Day")
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(daily, id: \.day) { row in
                        BarMark(x: .value("Day", row.day, unit: .day),
                                y: .value("Volume", row.externalKg))
                            .foregroundStyle(by: .value("Source", "External"))
                            .cornerRadius(2)
                        BarMark(x: .value("Day", row.day, unit: .day),
                                y: .value("Volume", row.bodyweightKg))
                            .foregroundStyle(by: .value("Source", "Bodyweight"))
                            .cornerRadius(2)
                    }
                }
                .chartForegroundStyleScale(["External": ProgressPalette.ramp(0),
                                            "Bodyweight": ProgressPalette.ramp(2)])
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartXAxisLabel("Training day")
                .chartYAxisLabel("Volume (\(units.label))")
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 200)
            }
            .padding(14)
            .cardSurface()
        }
    }

    // MARK: The movements behind each half

    @ViewBuilder
    // `value` escapes: it is captured by the row builder `ProgressCardList` stores.
    private func exerciseSection(title: String, rows: [ExerciseContribution],
                                 value: @escaping (ExerciseContribution) -> Double) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                ProgressCardList(items: rows) { row in
                    ContributionRow(
                        exId: row.exId,
                        name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                        detail: trainedOn(row),
                        value: Formulas.formatWeight(kg: value(row), units: units))
                }
            }
        }
    }

    /// The days this movement was actually trained — the question a split chart raises
    /// and a percentage can't answer.
    private func trainedOn(_ row: ExerciseContribution) -> String {
        let sets = "\(row.sets) set\(row.sets == 1 ? "" : "s")"
        let shown = row.days.prefix(3)
        guard !shown.isEmpty else { return sets }
        let list = shown.map { $0.formatted(.dateTime.day().month(.abbreviated)) }
            .joined(separator: ", ")
        let hidden = row.days.count - shown.count
        return hidden > 0 ? "\(sets) · \(list) +\(hidden)" : "\(sets) · \(list)"
    }
}
