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
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @State private var window = RangeSelection()

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }


    /// Days from the athlete's first activity to today — the range control offers only
    /// windows that actually contain something.
    private var historySpanDays: Int? {
        guard let first = ProgressAnalytics.firstActivity(history: history, doneDates: [])
        else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
    }

    private var muscleSets: [(muscle: Muscle, sets: Int)] {
        ProgressAnalytics.muscleSets(history: history, days: window.days ?? 3650,
                                     muscles: { catalog.exercise(id: $0)?.primaryMuscles ?? [] })
    }

    /// Push vs pull vs static volume within the window, from the catalog's force facet.
    private var forceSplit: [(label: String, volume: Double)] {
        let cutoff = window.days.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        } ?? .distantPast
        var byForce: [Force: Double] = [:]
        let load = self.load
        for entry in history where entry.date >= cutoff {
            guard let force = catalog.exercise(id: entry.exId)?.force else { continue }
            byForce[force, default: 0] += load.volumeKg(entry)
        }
        return [("Push", byForce[.push] ?? 0), ("Pull", byForce[.pull] ?? 0),
                ("Static", byForce[.static] ?? 0)].filter { $0.volume > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Muscle Balance").font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window, historySpanDays: historySpanDays)

                if muscleSets.isEmpty {
                    ProgressEmptyCard(text: "No attributed sets in this window yet.")
                } else {
                    muscleBars
                    if forceSplit.count > 1 { pushPull }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Ranked horizontal bars, not a donut.
    ///
    /// The task here is "which muscle am I under-training", which is a ranked comparison
    /// — and a ring cannot draw a muscle you trained zero sets of, which on a balance
    /// chart is the single most useful row. Seven slices also blew the colour budget and
    /// forced a wrapping legend that clipped. One hue, direct labels, no legend.
    private var muscleBars: some View {
        let ranked = muscleSets
        let top = Array(ranked.prefix(6))
        let other = ranked.dropFirst(6)
        let maxSets = max(1, top.first?.sets ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(top, id: \.muscle) { row in
                NavigationLink(value: ProgressRoute.muscle(row.muscle)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.muscle.displayName)
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(row.sets) set\(row.sets == 1 ? "" : "s")")
                                .font(.rounded(12, .heavy)).foregroundStyle(Color.text2)
                                .tabularNumbers()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.track)
                                Capsule().fill(Color.accent)
                                    .frame(width: max(4, geo.size.width * CGFloat(row.sets) / CGFloat(maxSets)))
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !other.isEmpty {
                Text("+ \(other.count) more muscle\(other.count == 1 ? "" : "s") · \(other.reduce(0) { $0 + $1.sets }) sets")
                    .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
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

}

// MARK: - L3: one muscle

struct MuscleDetailView: View {
    let muscle: Muscle
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @State private var window = RangeSelection()

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    @State private var query = ""


    /// Days from the athlete's first activity to today — the range control offers only
    /// windows that actually contain something.
    private var historySpanDays: Int? {
        guard let first = ProgressAnalytics.firstActivity(history: history, doneDates: [])
        else { return nil }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1)
    }

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
            ProgressAnalytics.weekBuckets(history: relevant, weeks: window.weeks ?? 104, load: load))
    }

    /// This muscle's exercises ranked by window volume.
    private var rankedExercises: [(exId: String, volume: Double)] {
        // Hoisted: `load` is a computed property, so reading it inside the reduce would
        // rebuild the resolver (re-sorting the whole bodyweight series) once per entry.
        let load = self.load
        return Dictionary(grouping: relevant, by: \.exId)
            .map { (exId: $0.key,
                    volume: $0.value.reduce(0.0) { sum, e in sum + load.volumeKg(e) })
            }
            .sorted { $0.volume > $1.volume }
    }

    private var filteredExercises: [(exId: String, volume: Double)] {
        let filter = ProgressListFilter(query: query)
        let keep = Set(filter.apply(to: rankedExercises.map(\.exId),
                                    catalog: { catalog.exercise(id: $0) }))
        return rankedExercises.filter { keep.contains($0.exId) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(muscle.displayName).font(.screenTitle).foregroundStyle(Color.textPrimary)
                RangePicker(selection: $window, historySpanDays: historySpanDays)

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
                    // The muscle is fixed by context here, so a name search is enough.
                    // Kept visible while a query is active even if the list has shrunk
                    // below the threshold, so the field that filtered it can also clear it.
                    if rankedExercises.count > 6 || !query.isEmpty {
                        SearchField(placeholder: "Search exercises", text: $query)
                    }
                    if filteredExercises.isEmpty {
                        ProgressEmptyCard(text: "No exercises match — clear the search above.")
                    } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredExercises.enumerated()), id: \.element.exId) { index, item in
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
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
