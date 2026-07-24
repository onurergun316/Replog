//
//  RepRangeDetailView.swift
//  Replog
//
//  Progress L3 — the rep-range mix, opened up.
//
//  "10 sets strength · 34 sets endurance" is a shape, not an explanation: the useful
//  question is which movements you train in which range, because that is what you'd
//  change. Each range lists the exercises that landed in it, ranked, with the days they
//  were trained — and each range says what it is *for*, since 1–5 vs 6–12 vs 13+ is a
//  training convention, not something the numbers announce on their own.
//

import SwiftUI
import SwiftData
import Charts

struct RepRangeDetailView: View {
    /// The window the mix was read in — `nil` is all time.
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

    private func mix(of rows: [ExerciseContribution]) -> RepRangeMix {
        rows.reduce(into: RepRangeMix()) { total, row in
            total.strength += row.mix.strength
            total.hypertrophy += row.mix.hypertrophy
            total.endurance += row.mix.endurance
        }
    }

    // One derivation per render: every reader used to re-walk history, JSON-decoding
    // every entry's sets on the way past.
    var body: some View {
        let rows = contributions
        let total = mix(of: rows)
        // Movements whose logged "reps" are seconds. They are excluded from every
        // rep-range count — a 45-second plank is not a set of 45 — so the screen says so
        // rather than letting its totals quietly disagree with the Volume screen's.
        let holds = rows.filter { load.isTimedHold(exId: $0.exId) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RangeSelection.label(days: days)).eyebrow()
                    Text("Rep Ranges").font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if total.total == 0 {
                    ProgressEmptyCard(text: "No counted sets in this window yet.")
                } else {
                    mixCard(total)
                    ForEach(RepRange.allCases) { range in
                        rangeSection(range, rows: rows, total: total)
                    }
                    if !holds.isEmpty { holdsSection(holds) }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mixCard(_ mix: RepRangeMix) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RepRangeBar(mix: mix)
            Divider()
            Text("\(mix.total) counted set\(mix.total == 1 ? "" : "s"). Rep ranges are a training convention, not a verdict: heavy sets bias toward strength, moderate sets toward size, high reps toward endurance, and most plans deliberately use more than one.")
                .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .cardSurface()
    }

    @ViewBuilder
    private func rangeSection(_ range: RepRange, rows all: [ExerciseContribution],
                              total: RepRangeMix) -> some View {
        let rows = all
            .filter { range.sets(in: $0.mix) > 0 }
            .sorted { range.sets(in: $0.mix) > range.sets(in: $1.mix) }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: range.title)
                    Text("\(range.sets(in: total)) set\(range.sets(in: total) == 1 ? "" : "s")")
                        .font(.rounded(11, .heavy)).foregroundStyle(Color.text3).tabularNumbers()
                }
                Text(range.purpose)
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressCardList(items: rows) { row in
                    ContributionRow(
                        exId: row.exId,
                        name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                        detail: trainedOn(row),
                        value: "\(range.sets(in: row.mix)) set\(range.sets(in: row.mix) == 1 ? "" : "s")")
                }
            }
        }
    }

    private func holdsSection(_ holds: [ExerciseContribution]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Timed Holds · Not Counted")
            Text("These log seconds rather than reps, so counting them would file a 45-second plank as a 45-rep endurance set.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            ProgressCardList(items: holds) { row in
                ContributionRow(
                    exId: row.exId,
                    name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                    detail: trainedOn(row),
                    value: "\(row.sets) set\(row.sets == 1 ? "" : "s")")
            }
        }
    }

    private func trainedOn(_ row: ExerciseContribution) -> String {
        let shown = row.days.prefix(3)
        guard !shown.isEmpty else { return "\(row.sessionCount) sessions" }
        let list = shown.map { $0.formatted(.dateTime.day().month(.abbreviated)) }
            .joined(separator: ", ")
        let hidden = row.days.count - shown.count
        return hidden > 0 ? "\(list) +\(hidden)" : list
    }
}

/// The three rep ranges, as something the UI can iterate rather than three copy-pasted
/// blocks that could drift apart.
enum RepRange: String, CaseIterable, Identifiable {
    case strength, hypertrophy, endurance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "1–5 Reps · Strength"
        case .hypertrophy: return "6–12 Reps · Hypertrophy"
        case .endurance: return "13+ Reps · Endurance"
        }
    }

    var purpose: String {
        switch self {
        case .strength:
            return "Heavy, low-rep work. Trains how much force you can produce, and most of the gain is neural rather than size."
        case .hypertrophy:
            return "Moderate loads taken close to failure. The range most plans spend the bulk of their sets in when the goal is muscle."
        case .endurance:
            return "Light loads for high reps. Builds work capacity and tendon resilience; a poor driver of maximal strength."
        }
    }

    func sets(in mix: RepRangeMix) -> Int {
        switch self {
        case .strength: return mix.strength
        case .hypertrophy: return mix.hypertrophy
        case .endurance: return mix.endurance
        }
    }
}
