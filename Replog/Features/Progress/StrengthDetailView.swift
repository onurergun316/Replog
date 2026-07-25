//
//  StrengthDetailView.swift
//  Replog
//
//  Progress L2 — Strength: estimated 1RM per lift over a chosen window, the PR feed, and
//  every trained exercise ranked. Rows push the exercise's own detail (L3), whose session
//  log is the deepest layer.
//
//  The filters sit above the chart because they drive it. Search and the muscle chips
//  narrow one set of exercises, and the chart, the PR feed and the list are all views of
//  that same set — a control that visibly reorders a list while the chart above it stays
//  frozen reads as a broken screen.
//
//  The chart picks its form from the data rather than always plotting time. One session
//  per lift is not a time series; drawn as one it is a field of unconnected dots with a
//  legend, which is what it used to be. With fewer than two sessions on every lift the
//  chart becomes the cross-section — how the lifts rank right now — which is a valid
//  reading from the very first session and turns into the trend as soon as one exists.
//

import SwiftUI
import SwiftData
import Charts

struct StrengthDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @State private var window = RangeSelection()

    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    /// The trained-exercise list is only useful if you can find a movement in it.
    @State private var filter = ProgressListFilter()

    private var filtered: [ExerciseProgress] {
        let ids = filter.apply(to: ranked.map(\.exId), catalog: { catalog.exercise(id: $0) })
        let keep = Set(ids)
        return ranked.filter { keep.contains($0.exId) }
    }

    private var muscleOptions: [Muscle] {
        ProgressListFilter.availableMuscles(in: ranked.map(\.exId),
                                            catalog: { catalog.exercise(id: $0) })
    }

    /// Days from the athlete's first activity to today — the range control offers only
    /// windows that actually contain something.
    private var historySpanDays: Int? {
        guard let first = ProgressAnalytics.firstActivity(history: history, doneDates: [])
        else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
    }

    private var cutoff: Date? {
        window.days.map { ProgressAnalytics.cutoff(days: $0) }
    }

    private var windowed: [HistoryEntry] {
        guard let cutoff else { return history }
        return history.filter { $0.date >= cutoff }
    }

    /// Every trained exercise summarized, best lift first.
    private var ranked: [ExerciseProgress] {
        let load = self.load
        return Dictionary(grouping: windowed, by: \.exId)
            .map { ProgressAggregator.summarize(exId: $0.key, history: $0.value, load: load) }
            .sorted { $0.bestE1rm > $1.bestE1rm }
    }

    /// PRs inside the window, narrowed to whatever the filters are showing — a feed that
    /// ignored the muscle chip would name lifts the rest of the screen has hidden.
    private var prs: [PREvent] {
        let visible = Set(filtered.map(\.exId))
        let events = ProgressAnalytics.prEvents(history: history, load: load)
            .filter { visible.contains($0.exId) }
        guard let cutoff else { return events }
        return events.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Strength").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window, historySpanDays: historySpanDays)

                if ranked.isEmpty {
                    ProgressEmptyCard(text: "No lifts in this window yet.")
                } else {
                    filterControls
                    if filtered.isEmpty {
                        ProgressEmptyCard(text: "No trained exercises match — clear the filters above.")
                    } else {
                        chartCard
                        prSection
                        SectionHeader(title: "All Exercises")
                        exerciseList
                    }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Filters — above the chart, because they drive it

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(placeholder: "Search your exercises", text: $filter.query)
            // Keep the chip row while a muscle is selected even if the window no longer
            // offers it — otherwise changing range hides the only control that could
            // clear the filter, stranding the athlete on an empty screen.
            if muscleOptions.count > 1 || filter.muscle != nil {
                FilterChipRow(options: muscleOptions.map { ($0, $0.displayName) },
                              selection: $filter.muscle,
                              allLabel: "All muscles")
            }
        }
    }

    // MARK: The chart

    /// Lifts with enough sessions in the window to draw a line. Ranked by how much
    /// history each has, so the three series plotted are the three with something to
    /// show rather than simply the three heaviest.
    private var plottable: [ExerciseProgress] {
        filtered
            .filter { $0.sessionCount >= 2 }
            .sorted { $0.sessionCount == $1.sessionCount ? $0.bestE1rm > $1.bestE1rm
                                                        : $0.sessionCount > $1.sessionCount }
            .prefix(3)
            .map { $0 }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(plottable.isEmpty ? "Where your lifts stand" : "Estimated 1RM over time")
                    .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                Spacer(minLength: 6)
                if let muscle = filter.muscle {
                    Pill(text: muscle.displayName, style: .accentSoft)
                }
            }
            if plottable.isEmpty { rankChart } else { trendChart }
            Text(caption)
                .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var caption: String {
        if plottable.isEmpty {
            let n = filtered.count
            return "\(n) lift\(n == 1 ? "" : "s") in this window, one session each — ranked by estimated 1RM rather than plotted over time. A second session on any of them draws the trend instead."
        }
        let names = plottable.map { name(of: $0.exId) }
        let language = ChartDensity.of(plottable.map(\.sessionCount).max() ?? 0)
        return "\(names.joined(separator: ", ")) · "
            + (language.allowsTrendLanguage ? "trend over the window" : "recent sessions, not yet a trend")
    }

    /// The cross-section: how the lifts rank right now. Valid at one session each, which
    /// is exactly when a time series is not.
    private var rankChart: some View {
        let top = Array(filtered.prefix(8))
        // Banded on the exercise id, never on the display name: names are clipped to fit
        // the axis, and the catalog has clusters sharing their first fifteen characters.
        // Two of those would band together and stack into one bar of their summed 1RM.
        return Chart(top, id: \.exId) { progress in
            BarMark(x: .value("Estimated 1RM", progress.bestE1rm),
                    y: .value("Exercise", progress.exId))
                .foregroundStyle(Color.accent)
                .cornerRadius(3)
                .annotation(position: .trailing) {
                    Text("\(progress.bestE1rm)")
                        .font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let exId = value.as(String.self) { Text(shortName(of: exId)) }
                }
            }
        }
        .chartXAxisLabel("Estimated 1RM")
        // Grows with the number of bars rather than squeezing eight lifts into 200pt.
        .frame(height: CGFloat(top.count) * 30 + 36)
    }

    /// The trend: one line per lift that has a history, over a padded, minimum-span axis.
    private var trendChart: some View {
        let series = plottable.flatMap { progress in
            windowed
                .filter { $0.exId == progress.exId }
                .sorted { $0.date < $1.date }
                .map { (name: name(of: progress.exId), date: $0.date, e1rm: load.e1rm($0)) }
        }
        let values = series.map { Double($0.e1rm) }
        let best = values.max() ?? 0
        let density = ChartDensity.of(plottable.map(\.sessionCount).max() ?? 0)
        return Chart(Array(series.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.e1rm))
                .foregroundStyle(by: .value("Exercise", point.name))
                // Smoothing invents curvature that isn't in a handful of sessions.
                .interpolationMethod(density.allowsSmoothing ? .monotone : .linear)
            // Points sit under the line rather than standing in for it, and drop away
            // once the line is dense enough to read on its own.
            if density.showsSymbols {
                PointMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.e1rm))
                    .foregroundStyle(by: .value("Exercise", point.name))
                    .symbolSize(34)
            }
        }
        .chartForegroundStyleScale(range: [ProgressPalette.ramp(0), ProgressPalette.ramp(1),
                                           ProgressPalette.ramp(2)])
        // Never `.automatic` alone: a 2.5kg PR on an auto-fitted axis reads as a doubling.
        .chartYScale(domain: ChartScales.yDomain(min: values.min() ?? 0, max: best,
                                                 minSpan: ChartScales.e1rmMinSpan(best: best)))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) {
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartXAxisLabel("Session date")
        .chartYAxisLabel("Estimated 1RM")
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 220)
    }

    // MARK: PRs

    @ViewBuilder
    private var prSection: some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Personal Records")
                ProgressCardList(items: Array(prs.prefix(10))) { pr in
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill").foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(of: pr.exId))
                                .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text(pr.date, format: .dateTime.month(.wide).day())
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                        }
                        Spacer(minLength: 6)
                        Text("\(pr.e1rm)").font(.rounded(16, .black))
                            .foregroundStyle(Color.accent).tabularNumbers()
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: The list

    private var exerciseList: some View {
        ProgressCardList(items: filtered) { progress in
            NavigationLink(value: ExerciseRef(id: progress.exId)) {
                HStack(spacing: 10) {
                    ExerciseThumbnail(
                        exercise: catalog.exercise(id: progress.exId),
                        size: 40, cornerRadius: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name(of: progress.exId))
                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(progress.sessionCount) session\(progress.sessionCount == 1 ? "" : "s")")
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    }
                    Spacer(minLength: 6)
                    TrendArrow(trend: progress.trend)
                    Text("\(progress.bestE1rm)")
                        .font(.rounded(16, .black)).foregroundStyle(Color.textPrimary)
                        .tabularNumbers()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func name(of exId: String) -> String {
        catalog.exercise(id: exId)?.name ?? exId
    }

    /// Axis labels have to fit a 393pt screen; the list below carries the full name.
    private func shortName(of exId: String) -> String {
        let full = name(of: exId)
        return full.count <= 16 ? full : String(full.prefix(15)) + "…"
    }
}

/// Shared empty-window card for the L2 screens.
struct ProgressEmptyCard: View {
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar").font(.system(size: 22)).foregroundStyle(Color.text3)
            Text(text).font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .cardSurface()
    }
}
