//
//  RecentHighlightSheet.swift
//  Replog
//
//  The story behind Today's "Recent Highlight".
//
//  The card is a name and a number. The number is the athlete's heaviest estimated 1RM
//  ever, which is the single most flattering fact the app holds about them — and tapping it
//  did nothing. This is what it was hiding: the set that produced it, the rest of that
//  session, which plan it was trained under, what it beat, and how the lift has moved since.
//
//  Dismiss-only via the grabber, like `StatDetailSheet` — nothing here is edited.
//

import SwiftUI

struct RecentHighlightSheet: View {
    let highlight: RecentHighlight
    let units: Units
    let catalog: ExerciseCatalog

    private var exercise: Exercise? { catalog.exercise(id: highlight.exId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if let line = beatLine { badge(line) }
                    attribution
                    if highlight.trail.count >= 2 { trailCard }
                    sessionCard
                    NavigationLink {
                        ExerciseDetailView(exId: highlight.exId, showProgress: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 14, weight: .bold))
                            Text("See full progress").font(.rounded(15, .heavy))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.accent)
                        .padding(14).cardSurface()
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Recent Highlight")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
    }

    // MARK: Pieces

    private var hero: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(exercise: exercise, size: 64, cornerRadius: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise?.name ?? highlight.exId)
                    .font(.rounded(19, .heavy)).foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Formulas.formatWeight(kg: Double(highlight.e1rm), units: units,
                                               includeUnit: false))
                        .font(.rounded(34, .black)).foregroundStyle(Color.accent).tabularNumbers()
                    Text("\(units.label) est. 1RM")
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// What the highlight beat, when it beat anything.
    private var beatLine: String? {
        if let gain = highlight.gainOverPreviousE1RM {
            let previous = Formulas.formatWeight(kg: Double(highlight.previousBestE1RM ?? 0), units: units)
            return "Personal best — \(Formulas.formatWeight(kg: Double(gain), units: units)) "
                + "over your previous \(previous)."
        }
        if highlight.sessionCount == 1 {
            return "The first time you logged this lift — every future session is measured against it."
        }
        return nil
    }

    private func badge(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.accent)
            Text(text)
                .font(.rounded(14, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.accentSoft))
    }

    /// When it happened, and what it was part of.
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("calendar", highlight.date.formatted(date: .abbreviated, time: .omitted))
            if let workout = highlight.workoutName {
                row("figure.strengthtraining.traditional",
                    [highlight.planName, workout].compactMap { $0 }.joined(separator: " · "))
            } else if let plan = highlight.planName {
                row("square.stack.3d.up", plan)
            }
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.text3)
                .frame(width: 18)
            Text(text).font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            Spacer(minLength: 0)
        }
    }

    /// Where this session sits in the lift's own line.
    private var trailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "This lift over time")
            VStack(alignment: .leading, spacing: 8) {
                Sparkline(values: highlight.trail.map(\.e1rm))
                    .frame(height: 44)
                HStack {
                    Text("\(highlight.sessionCount) session\(highlight.sessionCount == 1 ? "" : "s") logged")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    Spacer()
                    if let first = highlight.trail.first {
                        Text("from \(Formulas.formatWeight(kg: Double(first.e1rm), units: units))")
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    }
                }
            }
            .padding(14).cardSurface()
        }
    }

    /// Every set of the session that produced it, top set marked.
    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "That session")
            VStack(spacing: 0) {
                ForEach(Array(highlight.sets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text("Set \(index + 1)")
                            .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                            .frame(width: 52, alignment: .leading)
                        Text(setText(set))
                            .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                            .tabularNumbers()
                        Spacer(minLength: 8)
                        if index == topSetIndex {
                            Text("TOP SET")
                                .font(.rounded(10, .heavy)).foregroundStyle(Color.accent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentSoft))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    if index < highlight.sets.count - 1 { Divider().padding(.leading, 14) }
                }
                if highlight.sets.isEmpty {
                    Text("No sets recorded for that session.")
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .cardSurface()
        }
    }

    private func setText(_ set: RecordedSet) -> String {
        set.w == 0
            ? "\(set.r) reps"
            : "\(Formulas.formatWeight(kg: set.w, units: units)) × \(set.r)"
    }

    /// Which set the entry recorded as its top one. Matched on both numbers — so a session
    /// that repeated the weight for fewer reps isn't mislabelled — and only the first match
    /// is marked, since two identical sets are one top set done twice.
    private var topSetIndex: Int? {
        highlight.sets.firstIndex { $0.w == highlight.topWeightKg && $0.r == highlight.topReps }
    }
}
