//
//  ProgressHomeView.swift
//  Replog
//
//  Layer 1 of the Progress onion: the dashboard. A Calendar push card, then one chart
//  card per analytics domain — Strength (hero), Volume, Muscle Balance, Consistency,
//  Body — each a glanceable headline + mini chart that drills into its L2 screen.
//

import SwiftUI
import SwiftData
import Charts

struct ProgressHomeView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @Query private var settingsRows: [AppSettings]
    @State private var path = NavigationPath()

    /// One height for every mini chart, so the 2-up cards stay the same size — a taller
    /// bar chart beside a shorter one is what made the grid look unbalanced.
    private static let miniChartHeight: CGFloat = 56

    /// Read-only: `ReplogApp.init` bootstraps the singletons at launch precisely so no
    /// view body mutates the context. Fetch-or-create here would re-introduce that.
    private var doneDates: [Date] { profiles.first?.doneDates ?? [] }
    private var units: Units { settingsRows.first?.units ?? .kg }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }
    /// Credits bodyweight movements at their share of the athlete's weight.
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your training, in numbers").eyebrow()
                        Text("Progress").font(.screenTitle).foregroundStyle(Color.textPrimary)
                    }

                    calendarCard

                    if history.isEmpty {
                        emptyState
                    } else {
                        strengthCard
                        // A Grid, not two HStacks: an HStack sizes each child to its own
                        // ideal height, so a card whose headline scaled down or whose
                        // preview differed by a point sat visibly shorter than its
                        // neighbour. Grid offers both cells the row's height, and the
                        // card's flexible frame fills it — the pairs always match.
                        Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                            GridRow {
                                volumeCard
                                balanceCard
                            }
                            GridRow {
                                consistencyCard
                                bodyCard
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .progressNavigationDestinations()
        }
    }

    // MARK: Calendar

    private var calendarCard: some View {
        NavigationLink(value: ProgressRoute.calendar) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calendar").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                    Text("Every training day, tap or select a range")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.text3)
            }
            .padding(14)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    // MARK: Strength (hero)

    /// Every trained exercise summarised, strongest first.
    private var rankedLifts: [ExerciseProgress] {
        let load = self.load
        return Dictionary(grouping: history, by: \.exId)
            .map { ProgressAggregator.summarize(exId: $0.key, history: $0.value, load: load) }
            .sorted { $0.bestE1rm > $1.bestE1rm }
    }

    /// The top lift by best e1RM carries the hero card.
    private var topLift: ExerciseProgress? { rankedLifts.first }

    private var recentPRCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return ProgressAnalytics.prEvents(history: history, load: load).filter { $0.date >= cutoff }.count
    }

    @ViewBuilder
    private var strengthCard: some View {
        if let top = topLift {
            DashboardCard(
                eyebrow: "Strength",
                headline: "\(top.bestE1rm) est. 1RM",
                caption: "\(catalog.exercise(id: top.exId)?.name ?? top.exId)"
                    + (recentPRCount > 0 ? " · \(recentPRCount) PR\(recentPRCount == 1 ? "" : "s") this month" : ""),
                route: .strength
            ) {
                // Two forms, picked by what the data can support. With three or more
                // sessions of the headline lift, its own progression is the story —
                // bars, not a dotted line, because at 72pt a scatter reads as noise.
                // Below that there is no time series to draw, so the preview switches to
                // the cross-section: how the trained lifts rank against each other,
                // which is valid from the very first session.
                if top.series.count >= 3 {
                    MiniBars(values: top.series.suffix(20).map(Double.init), height: 72)
                } else {
                    MiniRankedBars(values: rankedLifts.prefix(5).map { Double($0.bestE1rm) },
                                   height: 72)
                }
            }
        }
    }

    // MARK: Volume

    private var weekBuckets: [WeekBucket] {
        ProgressAnalytics.trimmingLeadingEmptyWeeks(
            ProgressAnalytics.weekBuckets(history: history, weeks: 8, load: load))
    }

    /// The last few finished sessions' tonnage — the bucket that still has shape when
    /// the whole training history fits inside one week.
    private var recentSessionVolumes: [Double] {
        let load = self.load
        return ProgressAnalytics.sessions(history: history)
            .suffix(8)
            .map { ProgressAnalytics.tonnage(of: $0, load: load) }
    }

    private var volumeCard: some View {
        let buckets = weekBuckets
        let thisWeek = buckets.last?.volumeKg ?? 0
        return DashboardCard(
            eyebrow: "Volume",
            headline: Formulas.formatWeight(kg: thisWeek, units: units, includeUnit: false),
            caption: "\(units.label) this week",
            route: .volume
        ) {
            // The bucket follows the data. Two sessions inside one calendar week is a
            // single weekly bar — technically correct and completely shapeless — while
            // the same tonnage per session is a preview you can actually read.
            MiniBars(values: buckets.count >= 2 ? buckets.map(\.volumeKg) : recentSessionVolumes,
                     height: Self.miniChartHeight)
        }
    }

    // MARK: Muscle balance

    private var muscleShares: [(muscle: Muscle, sets: Int)] {
        ProgressAnalytics.muscleSets(history: history, days: 28,
                                     muscles: { catalog.exercise(id: $0)?.primaryMuscles ?? [] })
    }

    private var balanceCard: some View {
        let shares = Array(muscleShares.prefix(4))
        return DashboardCard(
            eyebrow: "Muscles",
            headline: shares.first?.muscle.displayName ?? "—",
            caption: shares.first.map { "\($0.sets) set\($0.sets == 1 ? "" : "s") in 4 weeks" },
            route: .balance
        ) {
            // Ranked bars, one hue — a mini donut cannot be read at 56pt and cannot
            // show a muscle trained zero times, which is the row that matters.
            Chart(shares, id: \.muscle) { row in
                BarMark(x: .value("Sets", row.sets),
                        y: .value("Muscle", row.muscle.displayName))
                    .foregroundStyle(Color.accent)
                    .cornerRadius(2)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: Self.miniChartHeight)
        }
    }

    // MARK: Consistency

    private var consistencyCard: some View {
        let weeks = ProgressAnalytics.adherence(
            scheduledDays: scheduledDays, doneDates: doneDates, weeks: 4,
            since: ProgressAnalytics.firstActivity(history: history, doneDates: doneDates))
        let scheduled = weeks.reduce(0) { $0 + $1.scheduled }
        let done = weeks.reduce(0) { $0 + $1.done }
        let percent = scheduled == 0 ? 0 : Int((Double(done) / Double(scheduled) * 100).rounded())
        return DashboardCard(
            eyebrow: "Consistency",
            headline: scheduled == 0 ? "—" : "\(percent)%",
            caption: "of scheduled days, 4 weeks",
            route: .consistency
        ) {
            if weeks.isEmpty {
                // No plan, so no denominator — the headline already says so. A flat
                // track keeps the card's geometry without pretending to be a reading.
                Capsule().fill(Color.track).frame(height: 8)
                    .frame(height: Self.miniChartHeight)
            } else {
                // Spans from zero so the done bar overlays the scheduled track rather
                // than stacking on top of it (see ConsistencyDetailView). Banded on the
                // week's position, not its date: one week of history on a time scale is
                // a bar with no width.
                Chart(Array(weeks.enumerated()), id: \.offset) { index, week in
                    BarMark(x: .value("Week", "\(index)"),
                            yStart: .value("From", 0), yEnd: .value("Scheduled", week.scheduled),
                            width: .ratio(0.62))
                        .foregroundStyle(Color.track)
                        .cornerRadius(3)
                    BarMark(x: .value("Week", "\(index)"),
                            yStart: .value("From", 0), yEnd: .value("Done", week.done),
                            width: .ratio(0.62))
                        .foregroundStyle(Color.accent)
                        .cornerRadius(3)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: Self.miniChartHeight)
            }
        }
    }

    // MARK: Body

    private var bodyCard: some View {
        let snapshot = BodyweightTracker.snapshot(entries: bodyweightEntries)
        let series = Array(bodyweightEntries.suffix(30))
        let weights = series.map(\.weightKg)
        return DashboardCard(
            eyebrow: "Body",
            headline: snapshot.map { Formulas.formatBodyweight(kg: $0.currentKg, units: units,
                                                              includeUnit: false) } ?? "—",
            caption: snapshot == nil ? "log your bodyweight" : units.label + " bodyweight",
            route: .body
        ) {
            if series.isEmpty {
                // Nothing to plot and nothing invented — a baseline the first check-in
                // will land on, so the card keeps the geometry of its neighbours.
                dashedBaseline
            } else {
                Chart {
                    // The first reading, as the line everything after it is measured
                    // against. At one check-in this is what stops a lone dot from
                    // floating in an empty frame.
                    if let first = weights.first {
                        RuleMark(y: .value("Start", first))
                            .foregroundStyle(Color.text3.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    ForEach(series, id: \.id) { entry in
                        if series.count >= 2 {
                            LineMark(x: .value("Date", entry.date),
                                     y: .value("Weight", entry.weightKg))
                                .foregroundStyle(Color.accent)
                                .interpolationMethod(series.count >= 8 ? .monotone : .linear)
                        }
                        PointMark(x: .value("Date", entry.date),
                                  y: .value("Weight", entry.weightKg))
                            .foregroundStyle(Color.accent)
                            .symbolSize(series.count >= 12 ? 20 : 34)
                    }
                }
                // Never `.automatic` alone: two readings a few hundred grams apart fill
                // the card and read as a cliff (ChartScales).
                .chartYScale(domain: ChartScales.yDomain(
                    min: weights.min() ?? 0, max: weights.max() ?? 0,
                    minSpan: ChartScales.bodyweightMinSpanKg))
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: Self.miniChartHeight)
            }
        }
    }

    private var dashedBaseline: some View {
        Rectangle()
            .fill(Color.text3.opacity(0.35))
            .frame(height: 1)
            .frame(height: Self.miniChartHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28)).foregroundStyle(Color.text3)
            Text("No training data yet").font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text("Finish a workout and your dashboard builds itself — volume, strength, balance, consistency.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .cardSurface()
    }
}
