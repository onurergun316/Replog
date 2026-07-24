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

    /// One force's share of the window.
    private typealias ForceGroup = (key: Force, volumeKg: Double, sets: Int,
                                    exercises: [ExerciseContribution])

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }
    private var windowDays: Int { days ?? RangeSelection.allTimeDays }

    private func force(of exId: String) -> Force? { catalog.exercise(id: exId)?.force }

    /// Colour is a property of the force, not of its current rank.
    ///
    /// The capsule and legend used to take `ramp(index * 2)` over volume-sorted groups
    /// while the day chart inferred its own domain from a dictionary's iteration order —
    /// so push could be dark in one chart and light in the other on the same screen, and
    /// differently again on the next launch. Fixing the mapping also stops a colour
    /// changing meaning just because the athlete pulled more than they pressed this week.
    private static let ramp: [Force: Int] = [.push: 0, .pull: 2, .static: 4]

    private func rampIndex(for force: Force) -> Int { Self.ramp[force] ?? 4 }
    private func color(for force: Force) -> Color { ProgressPalette.ramp(rampIndex(for: force)) }

    // One derivation per render, threaded down: each read of `contributions` re-walks the
    // whole history and JSON-decodes every entry's sets on the way past.
    var body: some View {
        let rows = ProgressAnalytics.exerciseContributions(history: history, days: windowDays,
                                                           load: load)
        let groups = ProgressAnalytics.grouped(rows) { force(of: $0.exId) }
        let total = groups.reduce(0.0) { $0 + $1.volumeKg }
        let perDay = ProgressAnalytics.dailyVolume(history: history, days: windowDays,
                                                   load: load, key: { force(of: $0) })
        // Movements the catalog doesn't classify. Named rather than silently dropped —
        // the percentages don't reconcile with the Volume screen's total without them.
        let unclassified = rows.filter { force(of: $0.exId) == nil }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RangeSelection.label(days: days)).eyebrow()
                    Text("Push · Pull").font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if groups.isEmpty {
                    ProgressEmptyCard(text: "Nothing classified as push or pull in this window yet.")
                } else {
                    splitCard(groups, total: total)
                    ratioCard(groups)
                    if perDay.count >= 2 { dailyChart(perDay) }
                    ForEach(groups, id: \.key) { group in
                        forceSection(group, total: total)
                    }
                    if !unclassified.isEmpty { unclassifiedSection(unclassified) }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: The split

    private func splitCard(_ groups: [ForceGroup], total: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(groups, id: \.key) { group in
                BarMark(x: .value("Volume", group.volumeKg))
                    .foregroundStyle(color(for: group.key))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .frame(height: 26)
            .clipShape(Capsule())
            ForEach(groups, id: \.key) { group in
                LegendRow(label: "\(group.key.displayName) · \(group.sets) set\(group.sets == 1 ? "" : "s")",
                          value: legend(group.volumeKg, of: total), ramp: rampIndex(for: group.key))
            }
        }
        .padding(14)
        .cardSurface()
    }

    private func legend(_ value: Double, of total: Double) -> String {
        let percent = total > 0 ? Int((value / total * 100).rounded()) : 0
        return "\(Formulas.formatWeight(kg: value, units: units)) · \(percent)%"
    }

    // MARK: The reading that matters

    @ViewBuilder
    private func ratioCard(_ groups: [ForceGroup]) -> some View {
        let push = groups.first { $0.key == .push }?.volumeKg ?? 0
        let pull = groups.first { $0.key == .pull }?.volumeKg ?? 0
        VStack(alignment: .leading, spacing: 6) {
            // A ratio needs both sides; with one of them at zero this is a division by
            // zero rather than an imbalance.
            if push > 0, pull > 0 {
                Text(String(format: "%.2f : 1", push / pull))
                    .font(.rounded(30, .black)).foregroundStyle(Color.textPrimary)
                    .tabularNumbers().lineLimit(1).minimumScaleFactor(0.6)
                Text("push to pull")
                    .font(.rounded(11, .bold)).foregroundStyle(Color.text2)
                Text(ratioReading(push / pull))
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                Text(push > 0 ? "All push, no pull" : "All pull, no push")
                    .font(.rounded(22, .black)).foregroundStyle(Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("A ratio needs both sides. Log some \(push > 0 ? "pulling" : "pressing") work and this becomes a reading.")
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

    private func dailyChart(_ daily: [(day: Date, key: Force, volumeKg: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Day By Day")
            VStack(alignment: .leading, spacing: 8) {
                Chart(Array(daily.enumerated()), id: \.offset) { _, row in
                    BarMark(x: .value("Day", row.day, unit: .day),
                            y: .value("Volume", Formulas.displayWeight(kg: row.volumeKg,
                                                                       units: units)))
                        .foregroundStyle(by: .value("Force", row.key.displayName))
                        .cornerRadius(2)
                }
                // Explicit domain→range pairs: with `range:` alone the mapping comes from
                // an inferred domain, which disagreed with the capsule above and wasn't
                // even stable between launches.
                .chartForegroundStyleScale(domain: Force.allCases.map(\.displayName),
                                           range: Force.allCases.map { color(for: $0) })
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

    private func forceSection(_ group: ForceGroup, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: group.key.displayName)
                Text(legend(group.volumeKg, of: total))
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

    private func unclassifiedSection(_ rows: [ExerciseContribution]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Not Classified")
            Text("The catalog records no push/pull direction for these, so they sit outside the split above.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            ProgressCardList(items: rows) { row in
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
