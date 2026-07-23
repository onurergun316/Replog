//
//  BodyDetailView.swift
//  Replog
//
//  Progress L2 — Body: the bodyweight trend over a chosen window, its rate of change,
//  relative strength (top lifts as multiples of bodyweight), and the recent readiness
//  picture from check-ins.
//

import SwiftUI
import SwiftData
import Charts

struct BodyDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @Query private var history: [HistoryEntry]
    @Query private var readinessEntries: [ReadinessEntry]
    @Query private var settingsRows: [AppSettings]
    @State private var window: RangeWindow = .sixMonths

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var snapshot: BodyweightSnapshot? { BodyweightTracker.snapshot(entries: bodyweightEntries) }
    /// Relative strength is the one reading that is meaningless without bodyweight credit:
    /// a pull-up would otherwise rank at 0.00x BW.
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    private var windowed: [BodyweightEntry] {
        guard let days = window.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return bodyweightEntries }
        return bodyweightEntries.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Body").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window)

                if windowed.isEmpty {
                    ProgressEmptyCard(text: "No bodyweight check-ins in this window — log one from Today.")
                } else {
                    summaryRow
                    weightChart
                }
                relativeStrengthSection
                readinessSection
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            tile(snapshot.map { Formulas.formatBodyweight(kg: $0.currentKg, units: units,
                                                          includeUnit: false) } ?? "—",
                 "current \(units.label)")
            tile(snapshot?.deltaKg.map { String(format: "%+.1f", $0) } ?? "—", "vs last check-in")
            tile(snapshot?.weeklyRateKg.map { String(format: "%+.2f/wk", $0) } ?? "—", "trend")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(17, .black)).foregroundStyle(Color.textPrimary)
                .tabularNumbers().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .cardSurface()
    }

    private var weightChart: some View {
        Chart(windowed, id: \.id) { entry in
            LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                .foregroundStyle(Color.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                .foregroundStyle(Color.accent)
                .symbolSize(20)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 200)
        .padding(14)
        .cardSurface()
    }

    /// Top lifts as bodyweight multiples — the classic strength-standards read.
    private var relativeStrengthSection: some View {
        let bw = snapshot?.currentKg
        let top = Dictionary(grouping: history, by: \.exId)
            .map { ProgressAggregator.summarize(exId: $0.key, history: $0.value, load: load) }
            .sorted { $0.bestE1rm > $1.bestE1rm }
            .prefix(3)
        return Group {
            if let bw, !top.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Relative Strength")
                    VStack(spacing: 0) {
                        ForEach(Array(top.enumerated()), id: \.element.exId) { index, progress in
                            if index > 0 { Divider() }
                            HStack {
                                Text(catalog.exercise(id: progress.exId)?.name ?? progress.exId)
                                    .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                let multiple = ProgressAnalytics.relativeStrength(
                                    e1rm: progress.bestE1rm, bodyweightKg: bw)
                                Text(multiple.map { String(format: "%.2f× BW", $0) } ?? "—")
                                    .font(.rounded(13, .heavy)).foregroundStyle(Color.accent)
                                    .tabularNumbers()
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
            }
        }
    }

    /// The last 14 days of check-ins, per dimension: how often each rating landed.
    private var readinessSection: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = readinessEntries.filter { $0.date >= cutoff }
        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Readiness · 14 days")
                    VStack(spacing: 10) {
                        readinessRow("Sleep", recent.map(\.sleep))
                        readinessRow("Soreness", recent.map(\.soreness))
                        readinessRow("Stress", recent.map(\.stress))
                    }
                    .padding(14)
                    .cardSurface()
                }
            }
        }
    }

    private func readinessRow(_ label: String, _ ratings: [ReadinessRating]) -> some View {
        let good = ratings.filter { $0 == .good }.count
        let moderate = ratings.filter { $0 == .moderate }.count
        let poor = ratings.filter { $0 == .poor }.count
        return HStack(spacing: 10) {
            Text(label).font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                .frame(width: 74, alignment: .leading)
            Chart {
                if good > 0 { BarMark(x: .value("n", good)).foregroundStyle(Color.up) }
                if moderate > 0 { BarMark(x: .value("n", moderate)).foregroundStyle(Color.accent.opacity(0.5)) }
                if poor > 0 { BarMark(x: .value("n", poor)).foregroundStyle(Color.down) }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 14)
            .clipShape(Capsule())
            Text("\(good)/\(ratings.count) good")
                .font(.rounded(11, .bold)).foregroundStyle(Color.text3)
        }
    }
}
