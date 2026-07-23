//
//  TrainingDayView.swift
//  Replog
//
//  Progress L4 — one training day: what was lifted, split by session when the day held
//  more than one, with every exercise pushing on to its own history.
//

import SwiftUI
import SwiftData

struct TrainingDayView: View {
    let day: Date

    @Environment(\.exerciseCatalog) private var catalog
    @Query private var history: [HistoryEntry]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]

    private var units: Units { settingsRows.first?.units ?? .kg }
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }

    private var onDay: [HistoryEntry] {
        history.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var sessions: [ProgressAnalytics.SessionGroup] {
        ProgressAnalytics.sessions(history: onDay)
    }

    private var totalVolume: Double { onDay.reduce(0.0) { $0 + load.volumeKg($1) } }
    private var totalSets: Int { onDay.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day, format: .dateTime.weekday(.wide)).eyebrow()
                    Text(day, format: .dateTime.month(.wide).day())
                        .font(.screenTitle).foregroundStyle(Color.textPrimary)
                }

                if onDay.isEmpty {
                    ProgressEmptyCard(text: "Nothing logged on this day.")
                } else {
                    summaryRow
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        sessionSection(session, index: index, of: sessions.count)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryRow: some View {
        let split = (external: onDay.reduce(0.0) { $0 + load.externalVolumeKg($1) },
                     bodyweight: onDay.reduce(0.0) { $0 + load.bodyweightVolumeKg($1) })
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                tile(Formulas.formatWeight(kg: totalVolume, units: units, includeUnit: false),
                     "total \(units.label)")
                tile("\(totalSets)", "sets")
                tile("\(onDay.count)", onDay.count == 1 ? "exercise" : "exercises")
            }
            // Where the tonnage came from — the blended headline shouldn't hide that
            // some of it was the athlete's own body.
            if split.bodyweight > 0, split.external > 0 {
                HStack(spacing: 6) {
                    Text("\(Formulas.formatWeight(kg: split.external, units: units)) external")
                    Text("·").foregroundStyle(Color.text3)
                    Text("\(Formulas.formatWeight(kg: split.bodyweight, units: units)) bodyweight")
                }
                .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .tabularNumbers().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .cardSurface()
    }

    @ViewBuilder
    private func sessionSection(_ session: ProgressAnalytics.SessionGroup,
                                index: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only name the session when the day held more than one — otherwise the
            // heading just repeats the screen title.
            SectionHeader(title: count > 1
                          ? (session.workoutName ?? "Session \(index + 1)")
                          : (session.workoutName ?? "Logged"))
            VStack(spacing: 0) {
                ForEach(Array(session.entries.sorted { load.e1rm($0) > load.e1rm($1) }.enumerated()),
                        id: \.element.id) { row, entry in
                    if row > 0 { Divider() }
                    NavigationLink(value: ExerciseRef(id: entry.exId)) {
                        HStack(spacing: 10) {
                            ExerciseThumbnail(
                                resourceName: catalog.exercise(id: entry.exId)?.imageResourceNames.first,
                                size: 40, cornerRadius: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(catalog.exercise(id: entry.exId)?.name ?? entry.exId)
                                    .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text(setSummary(entry))
                                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(Formulas.formatWeight(kg: load.volumeKg(entry), units: units))
                                .font(.rounded(12, .heavy)).foregroundStyle(Color.text2)
                                .tabularNumbers()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
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

    /// "3 sets · top 60kg × 8", or reps-only for a bodyweight movement whose logged
    /// weight is zero — printing "0kg × 8" there would be nonsense.
    private func setSummary(_ entry: HistoryEntry) -> String {
        let sets = "\(entry.sets.count) set\(entry.sets.count == 1 ? "" : "s")"
        guard entry.topR > 0 else { return sets }
        if entry.topW > 0 {
            return "\(sets) · top \(Formulas.formatWeight(kg: entry.topW, units: units)) × \(entry.topR)"
        }
        let isHold = catalog.exercise(id: entry.exId).map { BodyweightLoad.isTimedHold($0) } ?? false
        return isHold ? "\(sets) · best \(entry.topR)s" : "\(sets) · top \(entry.topR) reps"
    }
}
