//
//  CoachViews.swift
//  Replog
//
//  The coach's two surfaces: the post-session debrief sheet (appears after the celebration)
//  and the dismissible Today "Coach" card. Both render `CoachInsight`s produced by the pure
//  `CoachEngine`; the debrief sheet best-effort rewords them into coach voice via `CoachVoice`
//  (falling back to the deterministic text).
//

import SwiftUI

/// SF Symbol + tint for each insight kind.
extension CoachInsightKind {
    var symbol: String {
        switch self {
        case .sessionDebrief:   return "checkmark.seal.fill"
        case .stallAlert:       return "exclamationmark.triangle.fill"
        case .adherenceInsight: return "flame.fill"
        case .milestone:        return "trophy.fill"
        case .bodyweightTrend:  return "scalemass.fill"
        case .checkInPrompt:    return "calendar.badge.clock"
        case .readinessTrend:   return "bed.double.fill"
        case .welcome:          return "hand.wave.fill"
        }
    }

    var tint: Color {
        switch self {
        case .stallAlert:       return .down
        case .adherenceInsight: return .accent
        case .milestone:        return .up
        default:                return .accent
        }
    }
}

// MARK: - Debrief sheet

struct CoachDebriefView: View {
    let insights: [CoachInsight]
    /// Best-effort coach-voice rewording; falls back to the deterministic text.
    var voice: CoachVoice = CoachVoice()
    @Environment(\.dismiss) private var dismiss
    @State private var shown: [CoachInsight]

    init(insights: [CoachInsight], voice: CoachVoice = CoachVoice()) {
        self.insights = insights
        self.voice = voice
        _shown = State(initialValue: insights)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accent)
                    Text("Your Coach").eyebrow()
                }
                ForEach(shown) { insight in
                    CoachInsightRow(insight: insight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Session debrief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
            }
        }
        .task {
            // Reword in coach voice when Apple Intelligence is available (best-effort).
            let reworded = await voice.reword(insights)
            if reworded != shown { withAnimation(.snappy) { shown = reworded } }
        }
    }
}

/// A single insight row used in the debrief.
struct CoachInsightRow: View {
    let insight: CoachInsight
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(insight.kind.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                Text(insight.body)
                    .font(.bodyText).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
    }
}

// MARK: - Insights feed

/// The Profile "Coach Insights" section: a fixed-height, internally scrolling list.
///
/// The coaching log only grows, so rendering it flat pushed the Profile screen longer every
/// week. This keeps the section a constant size — about two cards tall, which is as much as
/// is worth reading at a glance — and scrolls inside itself. A grouping control switches
/// between when an insight happened and what kind it was, so a long history stays navigable.
struct CoachInsightsListView: View {
    let logs: [CoachingLog]

    enum Grouping: String, CaseIterable, Identifiable {
        case period, kind
        var id: String { rawValue }
        var title: String { self == .period ? "By date" : "By type" }
    }

    @State private var grouping: Grouping = .period
    /// Nil = every kind. Otherwise only that kind is listed.
    @State private var kindFilter: CoachInsightKind?

    /// Two cards plus a section header, with the next one just peeking so the list
    /// visibly affords scrolling.
    private let visibleHeight: CGFloat = 264

    private var filtered: [CoachingLog] {
        guard let kindFilter else { return logs }
        return logs.filter { $0.insightKind == kindFilter }
    }

    private var sections: [CoachInsightFeed.Section<CoachingLog>] {
        switch grouping {
        case .period: return CoachInsightFeed.byPeriod(filtered, date: \.date)
        case .kind:   return CoachInsightFeed.byKind(filtered, kind: \.insightKind, date: \.date)
        }
    }

    /// Only the kinds actually present, so the filter never offers an empty result.
    private var availableKinds: [CoachInsightKind] {
        let present = Set(logs.map(\.insightKind))
        return CoachInsightKind.allCases
            .filter { present.contains($0) }
            .sorted { $0.sortRank < $1.sortRank }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { log in
                                CoachInsightLogRow(log: log)
                            }
                        } header: {
                            Text(section.title)
                                .font(.rounded(12, .heavy))
                                .foregroundStyle(Color.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .background(Color.bg)
                        }
                    }
                    if sections.isEmpty {
                        Text("Nothing here yet.")
                            .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(height: visibleHeight)
            .scrollIndicators(.visible)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionHeader(title: "Coach Insights")
            Spacer(minLength: 0)
            Menu {
                Picker("Group by", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                }
                if !availableKinds.isEmpty {
                    Divider()
                    Picker("Show", selection: $kindFilter) {
                        Text("All insights").tag(CoachInsightKind?.none)
                        ForEach(availableKinds, id: \.self) { kind in
                            Text(kind.groupTitle).tag(CoachInsightKind?.some(kind))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .black))
                    Text(kindFilter?.groupTitle ?? grouping.title)
                        .font(.rounded(12, .heavy))
                }
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.accentSoft))
            }
            .accessibilityLabel("Group and filter coach insights")
        }
    }
}

/// One recorded insight in the Profile feed.
struct CoachInsightLogRow: View {
    let log: CoachingLog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: log.insightKind.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(log.insightKind.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(log.summary)
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                if let body = log.bodyMarkdown, !body.isEmpty {
                    Text(body).font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(log.date.formatted(.relative(presentation: .named)))
                    .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).cardSurface()
    }
}

// MARK: - Today card

/// The single, dismissible "Coach" card on Today. Shows the top-priority insight.
struct CoachCardView: View {
    let insight: CoachInsight
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(insight.kind.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Coach").eyebrow()
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.text3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss coach card")
                }
                Text(insight.title)
                    .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                Text(insight.body)
                    .font(.rounded(14, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.accentSoft))
    }
}
