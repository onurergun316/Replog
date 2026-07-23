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
    @State private var window = RangeSelection()

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var snapshot: BodyweightSnapshot? { BodyweightTracker.snapshot(entries: bodyweightEntries) }
    /// Relative strength is the one reading that is meaningless without bodyweight credit:
    /// a pull-up would otherwise rank at 0.00x BW.
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }


    /// Days from the athlete's first activity to today — the range control offers only
    /// windows that actually contain something.
    private var historySpanDays: Int? {
        guard let first = ProgressAnalytics.firstActivity(history: history, doneDates: [])
        else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
    }

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
                RangePicker(selection: $window, historySpanDays: historySpanDays)

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

    /// Tiles earn their place: a delta and a trend need a second and a third check-in to
    /// exist at all, and three tiles reading "—" tell a new athlete the screen is broken
    /// rather than that they have one weigh-in. Below that, say what is missing instead.
    @ViewBuilder
    private var summaryRow: some View {
        let current = snapshot.map {
            Formulas.formatBodyweight(kg: $0.currentKg, units: units, includeUnit: false)
        } ?? "—"
        HStack(spacing: 12) {
            tile(current, "current \(units.label)")
            if let delta = snapshot?.deltaKg {
                tile(String(format: "%+.1f", delta), "vs last check-in")
            }
            if let rate = snapshot?.weeklyRateKg {
                tile(String(format: "%+.2f", rate), "\(units.label) / week")
            }
            if snapshot?.deltaKg == nil {
                tile("\(bodyweightEntries.count)",
                     bodyweightEntries.count == 1 ? "check-in" : "check-ins")
            }
        }
        if snapshot?.deltaKg == nil, snapshot != nil {
            Text("Log another check-in and this becomes a trend.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
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

    /// A single check-in is one dot floating in a 200pt card, which looks like a
    /// rendering failure. Below two points the card states the reading in words instead.
    @ViewBuilder
    private var weightChart: some View {
        if windowed.count < 2 {
            if let only = windowed.last {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Formulas.formatBodyweight(kg: only.weightKg, units: units))
                        .font(.rounded(28, .black)).foregroundStyle(Color.textPrimary)
                        .tabularNumbers()
                    Text("Recorded \(only.date.formatted(.relative(presentation: .named))) — your starting point.")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .cardSurface()
            }
        } else {
            Chart(windowed, id: \.id) { entry in
                LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                    .foregroundStyle(Color.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                    .foregroundStyle(Color.accent)
                    .symbolSize(40)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 200)
            .padding(14)
            .cardSurface()
        }
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
