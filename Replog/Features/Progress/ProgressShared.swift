//
//  ProgressShared.swift
//  Replog
//
//  Shared vocabulary for the Progress onion: the time-range picker, the monochrome
//  chart ramp (data viz stays on-brand — distinguishable opacities of the accent,
//  never a rainbow), and the dashboard card chrome.
//

import SwiftUI

/// The L2 screens' time windows.
enum RangeWindow: String, CaseIterable, Identifiable {
    case fourWeeks, twelveWeeks, sixMonths, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fourWeeks: return "4W"
        case .twelveWeeks: return "12W"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    /// Number of weeks the window spans (`nil` = everything).
    var weeks: Int? {
        switch self {
        case .fourWeeks: return 4
        case .twelveWeeks: return 12
        case .sixMonths: return 26
        case .year: return 52
        case .all: return nil
        }
    }

    var days: Int? { weeks.map { $0 * 7 } }
}

/// The pill-row range picker used by every L2 screen.
struct RangePicker: View {
    @Binding var selection: RangeWindow

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RangeWindow.allCases) { window in
                let isSelected = window == selection
                Button { withAnimation(.snappy) { selection = window } } label: {
                    Text(window.label)
                        .font(.rounded(12, .heavy))
                        .foregroundStyle(isSelected ? .white : Color.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

enum ProgressPalette {
    /// Monochrome accent ramp for categorical marks (donut slices, stacked bars).
    static func ramp(_ index: Int) -> Color {
        let steps: [Double] = [1.0, 0.75, 0.55, 0.4, 0.28, 0.18]
        return Color.accent.opacity(steps[min(index, steps.count - 1)])
    }
}

/// L1 dashboard card chrome: eyebrow + headline row + a mini chart, all tappable.
///
/// Takes a `ProgressRoute` rather than a destination closure: a destination-based push
/// isn't represented in the stack's path, and mixing the two styles in one stack is
/// what made deeper exercise rows push-then-pop and pile up (see `ProgressNavigation`).
struct DashboardCard<Chart: View>: View {
    let eyebrow: String
    let headline: String
    var caption: String? = nil
    let route: ProgressRoute
    @ViewBuilder var chart: () -> Chart

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(eyebrow).font(.rounded(11, .heavy)).foregroundStyle(Color.text3)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
                }
                Text(headline).font(.rounded(20, .black)).foregroundStyle(Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7).tabularNumbers()
                if let caption {
                    Text(caption).font(.rounded(11, .semibold)).foregroundStyle(Color.text2)
                        .lineLimit(1)
                }
                chart()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
