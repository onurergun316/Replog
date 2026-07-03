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

extension CoachingLog {
    /// The `CoachInsightKind` a recorded coach-insight log represents (stored in payload tags),
    /// defaulting to a session debrief for older/plain records.
    var insightKind: CoachInsightKind {
        for tag in payload.tags {
            if let kind = CoachInsightKind(rawValue: tag) { return kind }
        }
        return .sessionDebrief
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
