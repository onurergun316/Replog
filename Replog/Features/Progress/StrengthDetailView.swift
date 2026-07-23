//
//  StrengthDetailView.swift
//  Replog
//
//  Progress L2 — Strength: the top lifts' e1RM trends over a chosen window, the PR
//  feed, and every trained exercise ranked by best e1RM. Rows push the exercise's own
//  detail (L3), whose session log is the deepest layer.
//

import SwiftUI
import SwiftData
import Charts

struct StrengthDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @State private var window: RangeWindow = .twelveWeeks

    private var cutoff: Date? {
        window.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }

    private var windowed: [HistoryEntry] {
        guard let cutoff else { return history }
        return history.filter { $0.date >= cutoff }
    }

    /// Every trained exercise summarized, best lift first.
    private var ranked: [ExerciseProgress] {
        Dictionary(grouping: windowed, by: \.exId)
            .map { ProgressAggregator.summarize(exId: $0.key, history: $0.value) }
            .sorted { $0.bestE1rm > $1.bestE1rm }
    }

    private var prs: [PREvent] {
        let events = ProgressAnalytics.prEvents(history: history)
        guard let cutoff else { return events }
        return events.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Strength").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window)

                if ranked.isEmpty {
                    ProgressEmptyCard(text: "No lifts in this window yet.")
                } else {
                    topLiftChart

                    if !prs.isEmpty {
                        SectionHeader(title: "Personal Records")
                        VStack(spacing: 0) {
                            ForEach(Array(prs.prefix(10).enumerated()), id: \.element.id) { index, pr in
                                if index > 0 { Divider() }
                                HStack(spacing: 10) {
                                    Image(systemName: "trophy.fill").foregroundStyle(Color.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(catalog.exercise(id: pr.exId)?.name ?? pr.exId)
                                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Text(pr.date, format: .dateTime.month(.wide).day())
                                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                                    }
                                    Spacer()
                                    Text("\(pr.e1rm)").font(.rounded(16, .black))
                                        .foregroundStyle(Color.accent).tabularNumbers()
                                }
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(.horizontal, 14)
                        .cardSurface()
                    }

                    SectionHeader(title: "All Exercises")
                    VStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.exId) { index, progress in
                            if index > 0 { Divider() }
                            NavigationLink(value: ExerciseRef(id: progress.exId)) {
                                HStack(spacing: 10) {
                                    ExerciseThumbnail(
                                        resourceName: catalog.exercise(id: progress.exId)?
                                            .imageResourceNames.first,
                                        size: 40, cornerRadius: 9)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(catalog.exercise(id: progress.exId)?.name ?? progress.exId)
                                            .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Text("\(progress.sessionCount) session\(progress.sessionCount == 1 ? "" : "s")")
                                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                                    }
                                    Spacer()
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
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The top three lifts' e1RM over time, one accent-ramp line each.
    private var topLiftChart: some View {
        let top = Array(ranked.prefix(3))
        let series = top.flatMap { progress in
            windowed
                .filter { $0.exId == progress.exId }
                .sorted { $0.date < $1.date }
                .map { (name: catalog.exercise(id: progress.exId)?.name ?? progress.exId,
                        date: $0.date, e1rm: $0.e1rm) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Chart(Array(series.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("1RM", point.e1rm))
                    .foregroundStyle(by: .value("Exercise", point.name))
                    .interpolationMethod(.monotone)
                // Most lifts have a single session early on, and a one-point line is
                // invisible — which is why this chart read as empty after two workouts.
                PointMark(x: .value("Date", point.date), y: .value("1RM", point.e1rm))
                    .foregroundStyle(by: .value("Exercise", point.name))
                    .symbolSize(40)
            }
            .chartForegroundStyleScale(range: [ProgressPalette.ramp(0), ProgressPalette.ramp(1),
                                               ProgressPalette.ramp(2)])
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 200)
        }
        .padding(14)
        .cardSurface()
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
