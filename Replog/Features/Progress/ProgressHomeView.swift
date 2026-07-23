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

    /// Read-only: `ReplogApp.init` bootstraps the singletons at launch precisely so no
    /// view body mutates the context. Fetch-or-create here would re-introduce that.
    private var doneDates: [Date] { profiles.first?.doneDates ?? [] }
    private var units: Units { settingsRows.first?.units ?? .kg }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }

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
                        HStack(alignment: .top, spacing: 12) {
                            volumeCard
                            balanceCard
                        }
                        HStack(alignment: .top, spacing: 12) {
                            consistencyCard
                            bodyCard
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

    /// The top lift by best e1RM carries the hero card.
    private var topLift: ExerciseProgress? {
        Dictionary(grouping: history, by: \.exId)
            .map { ProgressAggregator.summarize(exId: $0.key, history: $0.value) }
            .max { $0.bestE1rm < $1.bestE1rm }
    }

    private var recentPRCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return ProgressAnalytics.prEvents(history: history).filter { $0.date >= cutoff }.count
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
                Chart(Array(top.series.suffix(20).enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Session", index), y: .value("1RM", value))
                        .foregroundStyle(Color.accent)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Session", index), y: .value("1RM", value))
                        .foregroundStyle(LinearGradient(colors: [Color.accent.opacity(0.22), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 72)
            }
        }
    }

    // MARK: Volume

    private var weekBuckets: [WeekBucket] {
        ProgressAnalytics.weekBuckets(history: history, weeks: 8)
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
            Chart(buckets) { bucket in
                BarMark(x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                        y: .value("Volume", bucket.volumeKg))
                    .foregroundStyle(Color.accent.opacity(bucket.id == buckets.last?.id ? 1 : 0.45))
                    .cornerRadius(3)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 56)
        }
    }

    // MARK: Muscle balance

    private var muscleShares: [MuscleShare] {
        ProgressAnalytics.muscleShares(history: history, days: 28,
                                       muscles: { catalog.exercise(id: $0)?.primaryMuscles ?? [] })
    }

    private var balanceCard: some View {
        let shares = Array(muscleShares.prefix(5))
        return DashboardCard(
            eyebrow: "Muscles",
            headline: shares.first.map { $0.muscle.displayName } ?? "—",
            caption: shares.first.map { "\(Int(($0.share * 100).rounded()))% of 4-week volume" },
            route: .balance
        ) {
            Chart(Array(shares.enumerated()), id: \.element.id) { index, share in
                SectorMark(angle: .value("Volume", share.volumeKg),
                           innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(ProgressPalette.ramp(index))
                    .cornerRadius(2)
            }
            .frame(height: 56)
        }
    }

    // MARK: Consistency

    private var consistencyCard: some View {
        let weeks = ProgressAnalytics.adherence(scheduledDays: scheduledDays,
                                                doneDates: doneDates, weeks: 4)
        let scheduled = weeks.reduce(0) { $0 + $1.scheduled }
        let done = weeks.reduce(0) { $0 + $1.done }
        let percent = scheduled == 0 ? 0 : Int((Double(done) / Double(scheduled) * 100).rounded())
        return DashboardCard(
            eyebrow: "Consistency",
            headline: scheduled == 0 ? "—" : "\(percent)%",
            caption: "of scheduled days, 4 weeks",
            route: .consistency
        ) {
            Chart(weeks) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Scheduled", week.scheduled))
                    .foregroundStyle(Color.track)
                    .cornerRadius(3)
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Done", week.done))
                    .foregroundStyle(Color.accent)
                    .cornerRadius(3)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 56)
        }
    }

    // MARK: Body

    private var bodyCard: some View {
        let snapshot = BodyweightTracker.snapshot(entries: bodyweightEntries)
        let series = bodyweightEntries.suffix(30)
        return DashboardCard(
            eyebrow: "Body",
            headline: snapshot.map { Formulas.formatBodyweight(kg: $0.currentKg, units: units,
                                                              includeUnit: false) } ?? "—",
            caption: snapshot == nil ? "log your bodyweight" : units.label + " bodyweight",
            route: .body
        ) {
            Chart(Array(series), id: \.id) { entry in
                LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                    .foregroundStyle(Color.accent)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 56)
        }
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
