//
//  BalanceDetailView.swift
//  Replog
//
//  Progress L2 — Muscle Balance: the volume donut, push/pull split, and every muscle's
//  share; tapping a muscle opens its own L3 screen (volume trend + the exercises that
//  train it, which push on to L4 exercise detail).
//

import SwiftUI
import SwiftData
import Charts

struct BalanceDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @State private var window: RangeWindow = .fourWeeks

    private var units: Units { settingsRows.first?.units ?? .kg }

    private var shares: [MuscleShare] {
        ProgressAnalytics.muscleShares(history: history, days: window.days ?? 730,
                                       muscles: { catalog.exercise(id: $0)?.primaryMuscles ?? [] })
    }

    /// Push vs pull vs static volume within the window, from the catalog's force facet.
    private var forceSplit: [(label: String, volume: Double)] {
        let cutoff = window.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        } ?? .distantPast
        var byForce: [Force: Double] = [:]
        for entry in history where entry.date >= cutoff {
            guard let force = catalog.exercise(id: entry.exId)?.force else { continue }
            byForce[force, default: 0] += entry.sets.reduce(0.0) { $0 + $1.w * Double($1.r) }
        }
        return [("Push", byForce[.push] ?? 0), ("Pull", byForce[.pull] ?? 0),
                ("Static", byForce[.static] ?? 0)].filter { $0.volume > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Muscle Balance").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window)

                if shares.isEmpty {
                    ProgressEmptyCard(text: "No attributed volume in this window yet.")
                } else {
                    donut
                    if forceSplit.count > 1 { pushPull }
                    muscleList
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var donut: some View {
        let top = Array(shares.prefix(6))
        let other = shares.dropFirst(6).reduce(0.0) { $0 + $1.volumeKg }
        return VStack(spacing: 10) {
            Chart {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, share in
                    SectorMark(angle: .value("Volume", share.volumeKg),
                               innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(ProgressPalette.ramp(index))
                        .cornerRadius(3)
                }
                if other > 0 {
                    SectorMark(angle: .value("Volume", other),
                               innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(Color.track)
                        .cornerRadius(3)
                }
            }
            .frame(height: 190)
            FlowLayout(spacing: 8) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 5) {
                        Circle().fill(ProgressPalette.ramp(index)).frame(width: 7, height: 7)
                        Text("\(share.muscle.displayName) \(Int((share.share * 100).rounded()))%")
                            .font(.rounded(11, .bold)).foregroundStyle(Color.text2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var pushPull: some View {
        let total = forceSplit.reduce(0.0) { $0 + $1.volume }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Push · Pull")
            VStack(alignment: .leading, spacing: 8) {
                Chart(forceSplit, id: \.label) { item in
                    BarMark(x: .value("Volume", item.volume))
                        .foregroundStyle(by: .value("Force", item.label))
                }
                .chartForegroundStyleScale(range: [ProgressPalette.ramp(0), ProgressPalette.ramp(2),
                                                   ProgressPalette.ramp(4)])
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 26)
                .clipShape(Capsule())
                HStack(spacing: 14) {
                    ForEach(Array(forceSplit.enumerated()), id: \.element.label) { index, item in
                        HStack(spacing: 5) {
                            Circle().fill(ProgressPalette.ramp(index * 2)).frame(width: 7, height: 7)
                            Text("\(item.label) \(Int((item.volume / total * 100).rounded()))%")
                                .font(.rounded(11, .bold)).foregroundStyle(Color.text2)
                        }
                    }
                }
            }
            .padding(14)
            .cardSurface()
        }
    }

    private var muscleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By Muscle")
            VStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    if index > 0 { Divider() }
                    NavigationLink(value: ProgressRoute.muscle(share.muscle)) {
                        HStack(spacing: 10) {
                            Text(share.muscle.displayName)
                                .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(Int((share.share * 100).rounded()))%")
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
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }
}

// MARK: - L3: one muscle

struct MuscleDetailView: View {
    let muscle: Muscle
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @State private var window: RangeWindow = .twelveWeeks

    private var units: Units { settingsRows.first?.units ?? .kg }

    /// History entries whose exercise trains this muscle as a primary, within the window.
    private var relevant: [HistoryEntry] {
        let cutoff = window.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        } ?? .distantPast
        return history.filter {
            $0.date >= cutoff && catalog.exercise(id: $0.exId)?.primaryMuscles.contains(muscle) == true
        }
    }

    private var buckets: [WeekBucket] {
        ProgressAnalytics.trimmingLeadingEmptyWeeks(
            ProgressAnalytics.weekBuckets(history: relevant, weeks: window.weeks ?? 104))
    }

    /// This muscle's exercises ranked by window volume.
    private var rankedExercises: [(exId: String, volume: Double)] {
        Dictionary(grouping: relevant, by: \.exId)
            .map { (exId: $0.key,
                    volume: $0.value.reduce(0.0) { sum, e in
                        sum + e.sets.reduce(0.0) { $0 + $1.w * Double($1.r) } })
            }
            .sorted { $0.volume > $1.volume }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(muscle.displayName).font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window)

                if relevant.isEmpty {
                    ProgressEmptyCard(text: "Nothing logged for this muscle yet.")
                } else {
                    Chart(buckets) { bucket in
                        BarMark(x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                                y: .value("Volume", bucket.volumeKg))
                            .foregroundStyle(Color.accent)
                            .cornerRadius(3)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 160)
                    .padding(14)
                    .cardSurface()

                    SectionHeader(title: "Exercises")
                    VStack(spacing: 0) {
                        ForEach(Array(rankedExercises.enumerated()), id: \.element.exId) { index, item in
                            if index > 0 { Divider() }
                            NavigationLink(value: ExerciseRef(id: item.exId)) {
                                HStack(spacing: 10) {
                                    ExerciseThumbnail(
                                        resourceName: catalog.exercise(id: item.exId)?
                                            .imageResourceNames.first,
                                        size: 40, cornerRadius: 9)
                                    Text(catalog.exercise(id: item.exId)?.name ?? item.exId)
                                        .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(Formulas.formatWeight(kg: item.volume, units: units))
                                        .font(.rounded(12, .heavy)).foregroundStyle(Color.text2)
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
}
