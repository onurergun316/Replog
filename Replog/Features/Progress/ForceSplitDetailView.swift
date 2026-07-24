//
//  ForceSplitDetailView.swift
//  Replog
//
//  Progress L3 — push, pull and static, opened up.
//
//  The Muscle Balance screen states the split as one capsule and three percentages. The
//  reason anyone looks at it is the push-to-pull ratio — the imbalance that shows up as
//  a rounded posture and a cranky shoulder long before it shows up as a missed lift — so
//  this screen leads with that ratio, says what it means, then lists the movements on
//  each side and the days they were trained.
//

import SwiftUI
import SwiftData
import Charts

struct ForceSplitDetailView: View {
    /// The window the split was read in — `nil` is all time.
    let days: Int?

    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }
    private var windowDays: Int { days ?? 36_500 }

    private var contributions: [ExerciseContribution] {
        ProgressAnalytics.exerciseContributions(history: history, days: windowDays, load: load)
    }

    private func force(of exId: String) -> Force? { catalog.exercise(id: exId)?.force }

    private var groups: [(key: Force, volumeKg: Double, sets: Int, exercises: [ExerciseContribution])] {
        ProgressAnalytics.grouped(contributions) { force(of: $0.exId) }
    }

    private var daily: [(day: Date, key: Force, volumeKg: Double)] {
        ProgressAnalytics.dailyVolume(history: history, days: windowDays, load: load,
                                      key: { force(of: $0) })
    }

    private var total: Double { groups.reduce(0) { $0 + $1.volumeKg } }

    /// Movements the catalog doesn't classify. Named rather than silently dropped — the
    /// percentages below don't add up to the Volume screen's total without them.
    private var unclassified: [ExerciseContribution] {
        contributions.filter { force(of: $0.exId) == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RangeSelection.label(days: days)).eyebrow()
                    Text("Push · Pull").font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if groups.isEmpty {
                    ProgressEmptyCard(text: "Nothing classified as push or pull in this window yet.")
                } else {
                    splitCard
                    ratioCard
                    if daily.count >= 2 { dailyChart }
                    ForEach(groups, id: \.key) { group in
                        forceSection(group)
                    }
                    if !unclassified.isEmpty { unclassifiedSection }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: The split

    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(Array(groups.enumerated()), id: \.element.key) { index, group in
                BarMark(x: .value("Volume", group.volumeKg))
                    .foregroundStyle(ProgressPalette.ramp(index * 2))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .frame(height: 26)
            .clipShape(Capsule())
            ForEach(Array(groups.enumerated()), id: \.element.key) { index, group in
                LegendRow(label: "\(group.key.displayName) · \(group.sets) set\(group.sets == 1 ? "" : "s")",
                          value: legend(group.volumeKg), ramp: index * 2)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private func legend(_ value: Double) -> String {
        let percent = total > 0 ? Int((value / total * 100).rounded()) : 0
        return "\(Formulas.formatWeight(kg: value, units: units)) · \(percent)%"
    }

    // MARK: The reading that matters

    private var pushVolume: Double { groups.first { $0.key == .push }?.volumeKg ?? 0 }
    private var pullVolume: Double { groups.first { $0.key == .pull }?.volumeKg ?? 0 }

    /// Push tonnage per unit of pull tonnage. `nil` when one side is missing entirely,
    /// where a ratio is a division by zero rather than an imbalance.
    private var pushPullRatio: Double? {
        guard pushVolume > 0, pullVolume > 0 else { return nil }
        return pushVolume / pullVolume
    }

    @ViewBuilder
    private var ratioCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ratio = pushPullRatio {
                Text(String(format: "%.2f : 1", ratio))
                    .font(.rounded(30, .black)).foregroundStyle(Color.textPrimary)
                    .tabularNumbers().lineLimit(1).minimumScaleFactor(0.6)
                Text("push to pull")
                    .font(.rounded(11, .bold)).foregroundStyle(Color.text2)
                Text(ratioReading(ratio))
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                Text(pushVolume > 0 ? "All push, no pull" : "All pull, no push")
                    .font(.rounded(22, .black)).foregroundStyle(Color.textPrimary)
                Text("A ratio needs both sides. Log some \(pushVolume > 0 ? "pulling" : "pressing") work and this becomes a reading.")
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    /// Deliberately plain-language and hedged. This is tonnage, not a diagnosis: a
    /// deadlift day inflates pull the way a leg-press day inflates push, so the honest
    /// claim is about the balance of the *numbers*, with the usual convention alongside.
    private func ratioReading(_ ratio: Double) -> String {
        let common = "Most programmes aim for roughly even push and pull volume, and many coaches deliberately run pull-heavy to offset a pressing bias."
        switch ratio {
        case ..<0.7: return "Pull-heavy in this window. \(common)"
        case 0.7..<1.4: return "Close to even in this window. \(common)"
        default: return "Push-heavy in this window. \(common)"
        }
    }

    // MARK: When

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Day By Day")
            VStack(alignment: .leading, spacing: 8) {
                Chart(Array(daily.enumerated()), id: \.offset) { _, row in
                    BarMark(x: .value("Day", row.day, unit: .day),
                            y: .value("Volume", row.volumeKg))
                        .foregroundStyle(by: .value("Force", row.key.displayName))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(range: [ProgressPalette.ramp(0), ProgressPalette.ramp(2),
                                                   ProgressPalette.ramp(4)])
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

    // MARK: The movements

    private func forceSection(
        _ group: (key: Force, volumeKg: Double, sets: Int, exercises: [ExerciseContribution])
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: group.key.displayName)
                Text(legend(group.volumeKg))
                    .font(.rounded(11, .heavy)).foregroundStyle(Color.text3).tabularNumbers()
            }
            ProgressCardList(items: group.exercises) { row in
                ContributionRow(
                    exId: row.exId,
                    name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                    detail: trainedOn(row),
                    value: Formulas.formatWeight(kg: row.volumeKg, units: units))
            }
        }
    }

    private var unclassifiedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Not Classified")
            Text("The catalog records no push/pull direction for these, so they sit outside the split above.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            ProgressCardList(items: unclassified) { row in
                ContributionRow(
                    exId: row.exId,
                    name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                    detail: trainedOn(row),
                    value: Formulas.formatWeight(kg: row.volumeKg, units: units))
            }
        }
    }

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
