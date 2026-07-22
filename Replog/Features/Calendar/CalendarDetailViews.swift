//
//  CalendarDetailViews.swift
//  Replog
//
//  What shows under the Calendar's month grid: one day's training detail (exercises,
//  set-by-set, bodyweight), or the range summary for a multi-day selection — totals
//  plus per-training-day averages, the calendar-as-report-generator move from the
//  design bible.
//

import SwiftUI

// MARK: - One day

struct DayDetailView: View {
    let day: Date
    let isDone: Bool
    let entries: [HistoryEntry]
    let bodyweight: Double?
    let units: Units
    let catalog: ExerciseCatalog

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: isToday ? "Today"
                          : day.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())

            if entries.isEmpty && !isDone && bodyweight == nil {
                emptyCard
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if isDone && entries.isEmpty {
                        Label("Workout completed", systemImage: "checkmark.circle.fill")
                            .font(.rounded(14, .heavy)).foregroundStyle(Color.up)
                            .padding(.bottom, 4)
                        Text("No sets were saved for this day.")
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.vertical, 10) }
                        EntryRow(entry: entry, units: units, catalog: catalog)
                    }
                    if let bodyweight {
                        if !entries.isEmpty { Divider().padding(.vertical, 10) }
                        HStack(spacing: 8) {
                            Image(systemName: "scalemass").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.text2)
                            Text("Bodyweight").font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(Formulas.formatBodyweight(kg: bodyweight, units: units))
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: day > Date() ? "calendar" : "moon.zzz.fill")
                .font(.system(size: 24)).foregroundStyle(Color.text3)
            Text(day > Date() ? "Not trained yet" : "Rest day")
                .font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text(day > Date() ? "This day is still ahead of you."
                 : "Nothing logged on this day.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .cardSurface()
    }
}

/// One exercise logged on the day: thumbnail, name, top set, and the set-by-set list.
private struct EntryRow: View {
    let entry: HistoryEntry
    let units: Units
    let catalog: ExerciseCatalog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseThumbnail(resourceName: catalog.exercise(id: entry.exId)?.imageResourceNames.first,
                              size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(catalog.exercise(id: entry.exId)?.name ?? entry.exId)
                    .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(2)
                Text(setsLine)
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.e1rm)").font(.rounded(15, .black)).foregroundStyle(Color.accent)
                    .tabularNumbers()
                Text("est. 1RM").font(.rounded(10, .bold)).foregroundStyle(Color.text3)
            }
        }
    }

    private var setsLine: String {
        entry.sets
            .map { "\(Formulas.formatWeight(kg: $0.w, units: units, includeUnit: false))×\($0.r)" }
            .joined(separator: " · ")
    }
}

// MARK: - Range summary

struct RangeSummaryView: View {
    let summary: RangeSummary
    let units: Units
    let catalog: ExerciseCatalog
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "\(summary.selectedDays) days selected")
                Button(action: onClear) {
                    Text("Clear").font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentSoft))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    statTile("\(summary.trainingDays)", "training days")
                    statTile("\(summary.totalSets)", "sets")
                    statTile("\(summary.totalReps)", "reps")
                }
                HStack(spacing: 12) {
                    statTile(Formulas.formatWeight(kg: summary.totalVolumeKg, units: units,
                                                   includeUnit: false),
                             "volume (\(units.label))")
                    statTile("\(summary.distinctExercises)", "exercises")
                }

                if summary.trainingDays > 0 {
                    Divider()
                    Text("PER TRAINING DAY").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                    HStack(spacing: 12) {
                        statTile(String(format: "%.1f", summary.avgSetsPerTrainingDay), "sets / day")
                        statTile(Formulas.formatWeight(kg: summary.avgVolumePerTrainingDay,
                                                       units: units, includeUnit: false),
                                 "volume / day")
                    }
                }

                if let best = summary.bestLift {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill").foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(catalog.exercise(id: best.exId)?.name ?? best.exId)
                                .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                            Text("\(Formulas.formatWeight(kg: best.weightKg, units: units)) × \(best.reps) · \(best.e1rm) est. 1RM")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                        }
                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.rounded(20, .black)).foregroundStyle(Color.textPrimary).tabularNumbers()
            Text(label).font(.rounded(11, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
