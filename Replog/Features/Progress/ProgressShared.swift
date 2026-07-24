//
//  ProgressShared.swift
//  Replog
//
//  Shared vocabulary for the Progress onion: the time-range picker, the monochrome
//  chart ramp (data viz stays on-brand — distinguishable opacities of the accent,
//  never a rainbow), and the dashboard card chrome.
//

import SwiftUI
import Charts

/// The L2 screens' time windows.
enum RangeWindow: String, CaseIterable, Identifiable, Hashable {
    case fourWeeks, twelveWeeks, sixMonths, year, all
    /// A span the athlete picked themselves, in days.
    case custom
    var id: String { rawValue }

    static var allCases: [RangeWindow] { [.fourWeeks, .twelveWeeks, .sixMonths, .year, .all] }

    var label: String {
        switch self {
        case .fourWeeks: return "Last 4 weeks"
        case .twelveWeeks: return "Last 12 weeks"
        case .sixMonths: return "Last 6 months"
        case .year: return "Last year"
        case .all: return "All time"
        case .custom: return "Custom range"
        }
    }

    /// Number of weeks the window spans (`nil` = everything, or a custom span).
    var weeks: Int? {
        switch self {
        case .fourWeeks: return 4
        case .twelveWeeks: return 12
        case .sixMonths: return 26
        case .year: return 52
        case .all, .custom: return nil
        }
    }

    var days: Int? { weeks.map { $0 * 7 } }
}

/// A chosen window: a preset, or a custom number of days.
struct RangeSelection: Equatable {
    var window: RangeWindow = .all
    /// Only meaningful when `window == .custom`.
    var customDays: Int = 30

    /// Days the window spans, or `nil` for all time.
    var days: Int? { window == .custom ? customDays : window.days }
    var weeks: Int? { window == .custom ? max(1, Int(ceil(Double(customDays) / 7))) : window.weeks }

    var label: String {
        guard window == .custom else { return window.label }
        return customDays % 7 == 0
            ? "Last \(customDays / 7) week\(customDays / 7 == 1 ? "" : "s")"
            : "Last \(customDays) days"
    }
}

/// The range control used by every L2 screen.
///
/// A dropdown rather than a pill row, and it only offers windows that actually contain
/// something: with four days of history, "4W", "12W", "1Y" and "All" all render the
/// identical chart, so five pills that visibly do nothing read as a broken control. The
/// options are derived from `historySpanDays`, and a custom span is always available.
struct RangePicker: View {
    @Binding var selection: RangeSelection
    /// Days between the athlete's first activity and today. `nil` = nothing logged yet.
    var historySpanDays: Int?

    @State private var showingCustom = false

    /// Presets that reach past the data, plus the first one that fully contains it —
    /// so there is always a way to see everything without a wall of equivalent options.
    private var offered: [RangeWindow] {
        guard let span = historySpanDays else { return [.all] }
        var result: [RangeWindow] = []
        for window in RangeWindow.allCases {
            result.append(window)
            if let days = window.days, days >= span { break }   // this one already covers it
        }
        return result
    }

    var body: some View {
        // A control offering one option is not a control — with four days of history
        // every preset renders the identical chart, and five pills that visibly do
        // nothing read as broken.
        if offered.count > 1 || selection.window == .custom {
            picker
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Range", selection: Binding(
                    get: { selection.window },
                    set: { window in
                        if window == .custom { showingCustom = true } else { selection.window = window }
                    }
                )) {
                    ForEach(offered) { window in
                        Text(window.label).tag(window)
                    }
                    if selection.window == .custom {
                        Text(selection.label).tag(RangeWindow.custom)
                    }
                    Divider()
                    Text("Custom range…").tag(RangeWindow.custom)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.label)
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.text3)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color.surface2))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(isPresented: $showingCustom) {
            CustomRangeSheet(days: selection.customDays) { days in
                selection.customDays = days
                selection.window = .custom
            }
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Picks a custom span in days. Dismiss-only per the house sheet convention — the
/// stepper commits as it changes.
private struct CustomRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var days: Int
    let onCommit: (Int) -> Void

    init(days: Int, onCommit: @escaping (Int) -> Void) {
        _days = State(initialValue: days)
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show the last").eyebrow()
                Text("Custom range").font(.rounded(22, .black)).foregroundStyle(Color.textPrimary)
            }
            NumericStepperField(display: "\(days)", keyboard: .numberPad,
                                onMinus: { days = max(1, days - 7) },
                                onPlus: { days = min(3650, days + 7) },
                                onCommit: { raw in
                                    if let value = Int(raw.filter(\.isNumber)) {
                                        days = min(3650, max(1, value))
                                    }
                                })
            Text("days")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            Button {
                onCommit(days)
                dismiss()
            } label: {
                Text("Apply")
                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.bg.ignoresSafeArea())
    }
}

/// The L1 preview form: one axis-free bar per data point, newest at full accent.
///
/// The x scale is **categorical over the position**, not the date. Two sessions a day
/// apart on a time scale render as two hairlines pinned to the edges of the card; as
/// bands they read as two bars, which is the whole point of a preview. Apple's guidance
/// for a chart this small is no gridlines, no labels, no interaction — the number above
/// it carries the value, the bars carry the shape.
struct MiniBars: View {
    let values: [Double]
    /// Dims everything but the newest bar — off for a ranked cross-section, where every
    /// bar is a different subject rather than a step through time.
    var highlightsLast: Bool = true
    var height: CGFloat = 56

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            BarMark(x: .value("Position", "\(index)"),
                    y: .value("Value", value),
                    width: .ratio(0.62))
                .foregroundStyle(Color.accent.opacity(isDimmed(index) ? 0.45 : 1))
                .cornerRadius(3)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        // Bars are always zero-based; the headroom keeps the tallest bar off the ceiling.
        .chartYScale(domain: 0...max(0.0001, (values.max() ?? 0) * 1.15))
        .frame(height: height)
    }

    private func isDimmed(_ index: Int) -> Bool {
        highlightsLast && index != values.count - 1
    }
}

/// Ranked horizontal bars, one hue — the cross-section preview (lifts by e1RM, muscles
/// by sets). Valid from a single data point, which is what makes it the right form when
/// there is no time series to draw yet.
///
/// Banded on the row's position rather than its name, so two exercises that happen to
/// share a name can't collapse into one bar.
struct MiniRankedBars: View {
    /// Largest first.
    let values: [Double]
    var height: CGFloat = 56

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            BarMark(x: .value("Value", value),
                    y: .value("Rank", "\(index)"))
                .foregroundStyle(Color.accent)
                .cornerRadius(2)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: height)
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
///
/// Every card carries a preview. The earlier rule — draw a chart only once the data has
/// earned one, and let the card shrink otherwise — read as breakage on the dashboard:
/// two cards side by side in different sizes and shapes look like a layout bug, not like
/// restraint. So each card picks a *form its data supports* instead (per-session bars
/// before there are two weeks, a ranked cross-section before there is a time series)
/// rather than dropping to nothing. Same footprint, still no invented data.
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
            // `maxHeight` is what makes the 2-up rows match: the row is a Grid, so both
            // cells are offered the taller card's height and a flexible child fills it.
            // Without it, one wrapped line anywhere leaves two mismatched cards again.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
