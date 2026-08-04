//
//  BadgesView.swift
//  Replog
//
//  The trophy cabinet: a Profile card that opens the full board.
//
//  Locked badges are shown, not hidden. An empty slot with a grey silhouette is the whole
//  mechanic — it says there is something specific there to go and get, and the shape of it
//  is already visible. Progress on the near ones is spelled out ("7 / 10 workouts") because
//  a next rung you can see is what actually moves behaviour; a bare locked grid just reads
//  as a list of things you have failed to do.
//
//  Curiosities are the exception: they keep a vague hint while locked, on purpose.
//

import SwiftUI
import SwiftData

// MARK: - Profile entry point

/// The compact Profile card: a count, the most recent medals, and a way in.
struct BadgeSummaryCard: View {
    let awards: [BadgeAward]
    let snapshot: BadgeSnapshot

    private var earnedIds: Set<String> { Set(awards.map(\.badgeId)) }
    private var recent: [Badge] { awards.prefix(4).compactMap(\.badge) }
    private var upNext: [Badge] { BadgeEngine.upNext(in: snapshot, limit: 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(earnedIds.count)")
                    .font(.rounded(28, .black)).foregroundStyle(Color.textPrimary).tabularNumbers()
                Text("of \(BadgeCatalog.all.count) badges")
                    .font(.rounded(13, .bold)).foregroundStyle(Color.text2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text3)
            }
            HStack(spacing: 10) {
                // Earned ones first, then the nearest locked, so the row always says both
                // "here is what you have" and "here is what is close".
                ForEach(Array(display.enumerated()), id: \.offset) { _, item in
                    MedalView(badge: item.badge, earned: item.earned, size: 46)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private var display: [(badge: Badge, earned: Bool)] {
        let earned = recent.map { (badge: $0, earned: true) }
        let locked = upNext.prefix(max(0, 4 - earned.count)).map { (badge: $0, earned: false) }
        return Array((earned + locked).prefix(4))
    }
}

// MARK: - The board

struct BadgesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query(sort: \BadgeAward.earnedAt, order: .reverse) private var awards: [BadgeAward]

    /// Rebuilt when the screen appears; the board is read-only so it does not need to be live.
    @State private var snapshot = BadgeSnapshot()
    @State private var selected: Badge?
    @State private var showEarnedOnly = false

    private var awardsById: [String: BadgeAward] {
        Dictionary(awards.map { ($0.badgeId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(BadgeFamily.allCases) { family in
                    let badges = visibleBadges(in: family)
                    if !badges.isEmpty { section(family, badges: badges) }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { snapshot = BadgeAwarding.snapshot(context: context, catalog: catalog) }
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge, award: awardsById[badge.id],
                             progress: BadgeEngine.progress(badge.criterion, in: snapshot))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(awards.count)")
                    .font(.rounded(34, .black)).foregroundStyle(Color.textPrimary).tabularNumbers()
                Text("of \(BadgeCatalog.all.count) earned")
                    .font(.rounded(14, .bold)).foregroundStyle(Color.text2)
                Spacer(minLength: 0)
            }
            ProgressView(value: Double(awards.count), total: Double(max(1, BadgeCatalog.all.count)))
                .tint(Color.accent)
            Toggle("Earned only", isOn: $showEarnedOnly)
                .font(.rounded(13, .bold)).foregroundStyle(Color.text2)
                .tint(.accent)
        }
        .padding(16)
        .cardSurface()
    }

    private func visibleBadges(in family: BadgeFamily) -> [Badge] {
        let badges = BadgeCatalog.badges(in: family)
        return showEarnedOnly ? badges.filter { awardsById[$0.id] != nil } : badges
    }

    private func section(_ family: BadgeFamily, badges: [Badge]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: family.title)
                Text(family.blurb)
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(badges) { badge in
                    Button { selected = badge } label: {
                        BadgeTile(badge: badge, earned: awardsById[badge.id] != nil,
                                  progress: BadgeEngine.progress(badge.criterion, in: snapshot))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// One cell on the board.
private struct BadgeTile: View {
    let badge: Badge
    let earned: Bool
    let progress: BadgeEngine.Progress

    var body: some View {
        VStack(spacing: 6) {
            MedalView(badge: badge, earned: earned, size: 64)
            Text(badge.name)
                .font(.rounded(11, .heavy))
                .foregroundStyle(earned ? Color.textPrimary : Color.text3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Only when it is actually within reach: "0 / 500" on everything is noise.
            if !earned, !progress.isBinary, progress.fraction > 0 {
                Text(progress.label)
                    .font(.rounded(10, .bold)).foregroundStyle(Color.accent)
                    .tabularNumbers()
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail sheet

/// What a badge means, when it was won, and what it was won doing.
struct BadgeDetailSheet: View {
    let badge: Badge
    let award: BadgeAward?
    let progress: BadgeEngine.Progress

    @Environment(\.dismiss) private var dismiss

    private var earned: Bool { award != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MedalView(badge: badge, earned: earned, size: 148)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(badge.name)
                        .font(.rounded(24, .black)).foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(badge.family.title) · \(badge.tier.rawValue.capitalized)")
                        .font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
                }

                Text(earned ? badge.meaning : lockedText)
                    .font(.bodyText).foregroundStyle(Color.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                if earned { earnedDetail } else { lockedDetail }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// A curiosity keeps its secret; everything else says plainly what to go and do.
    private var lockedText: String {
        badge.revealsHintWhenLocked ? badge.hint : "\(badge.hint) You will know when it happens."
    }

    @ViewBuilder
    private var earnedDetail: some View {
        VStack(spacing: 0) {
            row("calendar", "Earned",
                award?.earnedAt.formatted(date: .abbreviated, time: .shortened) ?? "")
            if let plan = award?.planName, !plan.isEmpty {
                Divider().padding(.leading, 52)
                row("square.stack.3d.up", "Plan", plan)
            }
            if let workout = award?.workoutName, !workout.isEmpty {
                Divider().padding(.leading, 52)
                row("figure.strengthtraining.traditional", "Workout", workout)
            }
            if let detail = award?.detail, !detail.isEmpty {
                Divider().padding(.leading, 52)
                row("checkmark.seal", "Where you were", detail)
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private var lockedDetail: some View {
        if !progress.isBinary, progress.fraction > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress").font(.rounded(12, .heavy)).foregroundStyle(Color.text3)
                    Spacer()
                    Text(progress.label)
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.accent).tabularNumbers()
                }
                ProgressView(value: progress.fraction).tint(Color.accent)
            }
            .padding(16)
            .cardSurface()
        } else {
            Text("Not earned yet.")
                .font(.rounded(13, .bold)).foregroundStyle(Color.text3)
                .frame(maxWidth: .infinity)
                .padding(16)
                .cardSurface()
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentSoft))
            Text(title).font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}

// MARK: - Newly earned

/// The "you just earned this" sheet after a session, when one or more landed.
struct BadgeUnlockSheet: View {
    let badges: [Badge]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(badges.count == 1 ? "New badge" : "\(badges.count) new badges")
                    .font(.rounded(22, .black)).foregroundStyle(Color.textPrimary)
                    .padding(.top, 16)
                ForEach(badges) { badge in
                    HStack(spacing: 14) {
                        MedalView(badge: badge, earned: true, size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(badge.name)
                                .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                            Text(badge.meaning)
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
                }
                Button { dismiss() } label: {
                    Text("Nice").font(.rounded(16, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
