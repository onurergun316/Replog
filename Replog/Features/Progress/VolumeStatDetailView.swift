//
//  VolumeStatDetailView.swift
//  Replog
//
//  Progress L3 — one Volume headline, opened up.
//
//  "23,188 kg", "11,594 avg / session" and "44 sets" sat at the top of the Volume screen
//  as three numbers you could read and nothing else. Each of them is a sum over the same
//  rows (`ProgressAnalytics.exerciseContributions`), so each of them can say what it is
//  made of: which exercises produced it, over which sessions, on which days.
//
//  One screen, three readings, because the plumbing — window, resolver, units — is
//  identical and only the question changes.
//

import SwiftUI
import SwiftData
import Charts

/// Which Volume headline is being opened. One case per tile, so the screen always opens
/// on the reading that was tapped rather than a near neighbour of it.
enum VolumeStat: String, Hashable, CaseIterable {
    case total, average, weeklyAverage, sets

    var title: String {
        switch self {
        case .total: return "Total volume"
        case .average: return "Average session"
        case .weeklyAverage: return "Average week"
        case .sets: return "Sets"
        }
    }

    /// What the number actually measures, in one sentence. A statistic nobody can define
    /// is a statistic nobody trusts.
    var definition: String {
        switch self {
        case .total:
            return "Every kilogram you moved in this window: weight × reps for each set, with bodyweight movements credited at their share of your bodyweight."
        case .average:
            return "Total volume divided by the number of finished sessions — what a typical workout weighs in this window."
        case .weeklyAverage:
            return "Total volume divided by the weeks you actually trained in. Weeks with nothing logged are left out, so a holiday doesn't halve the number."
        case .sets:
            return "Every set you completed and logged. Sets, not kilograms, are the unit training volume is usually prescribed in."
        }
    }

    /// Whether this reading is about sessions over time rather than a composition.
    var listsSessions: Bool { self != .sets }
}

struct VolumeStatDetailView: View {
    let stat: VolumeStat
    /// The window the number was read in — `nil` is all time.
    let days: Int?

    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    /// Filtered through the same start-of-day cutoff the aggregates use, so the session
    /// list can't omit a session that the totals above it counted.
    private var windowed: [HistoryEntry] {
        let cutoff = ProgressAnalytics.cutoff(days: days ?? RangeSelection.allTimeDays)
        return history.filter { $0.date >= cutoff }
    }

    private var sessions: [ProgressAnalytics.SessionGroup] {
        ProgressAnalytics.sessions(history: windowed)
    }

    private var contributions: [ExerciseContribution] {
        ProgressAnalytics.exerciseContributions(history: history,
                                                days: days ?? RangeSelection.allTimeDays,
                                                load: load)
    }

    // One derivation per render, threaded down: each read of `contributions` or
    // `sessions` re-walks the history, JSON-decoding every entry's sets on the way past.
    var body: some View {
        let rows = contributions
        let groups = sessions
        let volume = rows.reduce(0.0) { $0 + $1.volumeKg }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RangeSelection.label(days: days)).eyebrow()
                    Text(stat.title).font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if rows.isEmpty {
                    ProgressEmptyCard(text: "No sets logged in this window yet.")
                } else {
                    headlineCard(rows: rows, sessions: groups, volume: volume)
                    chartSection(rows: rows, sessions: groups)
                    exerciseSection(rows: rows, volume: volume)
                    if stat.listsSessions { sessionSection(groups) }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Headline

    /// Weeks with at least one logged set inside the window — the denominator the Volume
    /// screen's "avg / week" tile uses, so both sides divide by the same number.
    private var trainedWeeks: Int {
        ProgressAnalytics.weekBuckets(history: history,
                                      weeks: days.map { max(1, Int(ceil(Double($0) / 7))) }
                                          ?? RangeSelection.allTimeWeeks,
                                      load: load)
            .filter { $0.volumeKg > 0 }.count
    }

    private func headlineValue(rows: [ExerciseContribution],
                               sessions: [ProgressAnalytics.SessionGroup],
                               volume: Double) -> String {
        switch stat {
        case .total: return Formulas.formatWeight(kg: volume, units: units)
        case .average:
            return Formulas.formatWeight(kg: volume / Double(max(1, sessions.count)), units: units)
        case .weeklyAverage:
            return Formulas.formatWeight(kg: volume / Double(max(1, trainedWeeks)), units: units)
        case .sets: return "\(rows.reduce(0) { $0 + $1.sets })"
        }
    }

    private func headlineCard(rows: [ExerciseContribution],
                              sessions: [ProgressAnalytics.SessionGroup],
                              volume: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headlineValue(rows: rows, sessions: sessions, volume: volume))
                .font(.rounded(30, .black)).foregroundStyle(Color.textPrimary)
                .tabularNumbers().lineLimit(1).minimumScaleFactor(0.6)
            Text(stat.definition)
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    // MARK: Charts — a different question per stat, not the same bars three times

    @ViewBuilder
    private func chartSection(rows: [ExerciseContribution],
                              sessions: [ProgressAnalytics.SessionGroup]) -> some View {
        switch stat {
        case .total: exerciseRankChart(rows)
        case .average, .weeklyAverage: sessionAverageChart(sessions)
        case .sets: setsChart(rows: rows, sessions: sessions)
        }
    }

    /// Where the total came from: the exercises that produced it, ranked. A total is a
    /// composition question, so the chart is the composition, not the timeline — that is
    /// what the session list below is for.
    private func exerciseRankChart(_ contributions: [ExerciseContribution]) -> some View {
        let top = Array(contributions.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Biggest Contributors")
            VStack(alignment: .leading, spacing: 8) {
                Chart(top) { row in
                    BarMark(x: .value("Volume", row.volumeKg),
                            y: .value("Exercise", shortName(row.exId)))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxisLabel("Volume (\(units.label))")
                .frame(height: CGFloat(top.count) * 26 + 34)
                if contributions.count > top.count {
                    Text("+ \(contributions.count - top.count) more exercise\(contributions.count - top.count == 1 ? "" : "s")")
                        .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                }
            }
            .padding(14)
            .cardSurface()
        }
    }

    /// Every session against the average, so "typical" has something to be typical of.
    private func sessionAverageChart(_ groups: [ProgressAnalytics.SessionGroup]) -> some View {
        let density = ChartDensity.of(groups.count)
        let load = self.load
        let tonnages = groups.map { ProgressAnalytics.tonnage(of: $0, load: load) }
        let average = tonnages.isEmpty ? 0 : tonnages.reduce(0, +) / Double(tonnages.count)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Every Session vs Average")
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    // No `unit: .day`: Swift Charts stacks marks that share an x value,
                    // so banding on the day silently merged two workouts done on the same
                    // day into one bar — on a chart whose whole subject is per-session.
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, session in
                        BarMark(x: .value("Session", session.date),
                                y: .value("Volume", tonnages[index]))
                            .foregroundStyle(tonnages[index] >= average
                                             ? Color.accent : Color.accent.opacity(0.45))
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Color.text3)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg \(Formulas.formatWeight(kg: average, units: units))")
                                .font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                        }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartXAxisLabel("Session date")
                .chartYAxisLabel("Volume (\(units.label))")
                .frame(height: max(160, density.chartHeight))
                Text("\(above(tonnages, average)) of \(groups.count) session\(groups.count == 1 ? "" : "s") at or above average")
                    .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
            }
            .padding(14)
            .cardSurface()
        }
    }

    /// Sets per session, with the rep ranges they landed in — the two readings that make
    /// a set count mean something.
    private func setsChart(rows: [ExerciseContribution],
                           sessions groups: [ProgressAnalytics.SessionGroup]) -> some View {
        let counts = groups.map(\.setCount)
        let mix = rows.reduce(into: RepRangeMix()) { total, row in
            total.strength += row.mix.strength
            total.hypertrophy += row.mix.hypertrophy
            total.endurance += row.mix.endurance
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sets Per Session")
            VStack(alignment: .leading, spacing: 10) {
                Chart(Array(groups.enumerated()), id: \.element.id) { index, session in
                    // Per session, so no `unit: .day` — see `sessionAverageChart`.
                    BarMark(x: .value("Session", session.date),
                            y: .value("Sets", counts[index]))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartXAxisLabel("Session date")
                .chartYAxisLabel("Sets")
                .frame(height: 180)
                if mix.total > 0 {
                    Divider()
                    RepRangeBar(mix: mix)
                }
            }
            .padding(14)
            .cardSurface()
        }
    }

    // MARK: Lists

    private func exerciseSection(rows: [ExerciseContribution], volume: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By Exercise")
            ProgressCardList(items: rows) { row in
                ContributionRow(
                    exId: row.exId,
                    name: catalog.exercise(id: row.exId)?.name ?? row.exId,
                    detail: detail(for: row),
                    value: value(for: row, of: volume))
            }
        }
    }

    private func detail(for row: ExerciseContribution) -> String {
        var parts: [String] = ["\(row.sets) set\(row.sets == 1 ? "" : "s")"]
        parts.append("\(row.sessionCount) session\(row.sessionCount == 1 ? "" : "s")")
        if let last = row.lastTrained {
            parts.append("last \(last.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return parts.joined(separator: " · ")
    }

    private func value(for row: ExerciseContribution, of volume: Double) -> String {
        switch stat {
        case .sets: return "\(row.sets)"
        case .total, .average, .weeklyAverage:
            let share = volume > 0 ? Int((row.volumeKg / volume * 100).rounded()) : 0
            return "\(Formulas.formatWeight(kg: row.volumeKg, units: units)) · \(share)%"
        }
    }

    private func sessionSection(_ sessions: [ProgressAnalytics.SessionGroup]) -> some View {
        let groups = sessions.reversed()
        let load = self.load
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By Session")
            ProgressCardList(items: Array(groups)) { session in
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
                        Spacer(minLength: 6)
                        Text(Formulas.formatWeight(kg: ProgressAnalytics.tonnage(of: session, load: load),
                                                   units: units))
                            .font(.rounded(13, .heavy)).foregroundStyle(Color.text2).tabularNumbers()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Helpers

    /// Axis labels have to stay inside a 393pt screen, so the chart gets a clipped name
    /// and the list below carries the full one.
    private func shortName(_ exId: String) -> String {
        let name = catalog.exercise(id: exId)?.name ?? exId
        return name.count <= 16 ? name : String(name.prefix(15)) + "…"
    }

    private func above(_ values: [Double], _ average: Double) -> Int {
        values.filter { $0 >= average }.count
    }
}
