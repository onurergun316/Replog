//
//  BodyweightCheckIn.swift
//  Replog
//
//  The periodic bodyweight check-in: a Today card showing the current weight + trend
//  (or a first-log prompt), and the entry sheet it opens. Logic in `BodyweightTracker`;
//  writes go through `ModelContext.logBodyweight`.
//

import SwiftUI

// MARK: - Today card

struct BodyweightCard: View {
    /// Nil until the first check-in is logged.
    let snapshot: BodyweightSnapshot?
    let due: Bool
    let units: Units
    let goal: Goal
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let snapshot {
                trendContent(snapshot)
                    .padding(14)
                    .cardSurface()
            } else {
                promptContent
                    .padding(14)
                    .cardSurface(fill: Color.accentSoft)
            }
        }
        .buttonStyle(.plain)
    }

    /// First-run state: no series yet, invite the first log.
    private var promptContent: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly check-in").eyebrow()
                Text("Log your bodyweight").font(.cardTitle).foregroundStyle(Color.textPrimary)
            }
            Spacer()
            Text("Log").font(.rounded(14, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.accent))
        }
    }

    private func trendContent(_ snapshot: BodyweightSnapshot) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(Formulas.formatBodyweight(kg: snapshot.currentKg, units: units))
                    .font(.metric).foregroundStyle(Color.textPrimary).tabularNumbers()
                HStack(spacing: 5) {
                    TrendArrow(trend: snapshot.direction)
                    Text(rateText(snapshot))
                        .font(.rounded(12, .bold))
                        .foregroundStyle(rateTint(snapshot))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Sparkline(values: snapshot.sparklineValues, color: .accent)
                    .frame(width: 72, height: 26)
                Text(due ? "Check in due" : snapshot.date.formatted(.relative(presentation: .named)))
                    .font(.rounded(11, .bold))
                    .foregroundStyle(due ? Color.accent : Color.text3)
            }
        }
    }

    private var icon: some View {
        Image(systemName: "scalemass.fill")
            .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.accentSoft))
    }

    private func rateText(_ snapshot: BodyweightSnapshot) -> String {
        guard let rate = snapshot.weeklyRateKg else { return "First check-in logged" }
        if snapshot.direction == .flat { return "Holding steady" }
        let sign = rate > 0 ? "+" : "-"
        return "\(sign)\(Formulas.formatBodyweight(kg: abs(rate), units: units))/week"
    }

    private func rateTint(_ snapshot: BodyweightSnapshot) -> Color {
        switch BodyweightTracker.isFavorable(snapshot.direction, for: goal) {
        case true: return .up
        case false: return .down
        default: return .text2
        }
    }
}

// MARK: - Entry sheet

struct BodyweightCheckInSheet: View {
    let initialKg: Double
    let units: Units
    /// e.g. "Last check-in: 77kg · 5 days ago" (nil on the first log).
    let lastCheckInLine: String?
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightKg: Double

    private static let rangeKg = 20.0...400.0

    init(initialKg: Double, units: Units, lastCheckInLine: String?, onSave: @escaping (Double) -> Void) {
        self.initialKg = initialKg
        self.units = units
        self.lastCheckInLine = lastCheckInLine
        self.onSave = onSave
        _weightKg = State(initialValue: Self.rangeKg.clamped(initialKg))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Weigh yourself at the same time of day — first thing in the morning is most consistent.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentSoft))
                    Text("Bodyweight").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    NumericStepperField(
                        display: Formulas.formatBodyweight(kg: weightKg, units: units, includeUnit: false),
                        keyboard: .decimalPad,
                        onMinus: { step(-1) },
                        onPlus: { step(+1) },
                        onCommit: { raw in
                            if let kg = Formulas.parseWeightKg(raw, units: units) {
                                weightKg = Self.rangeKg.clamped(kg)
                            }
                        })
                    Text(units.label).font(.rounded(11, .bold)).foregroundStyle(Color.text3)
                }
                .padding(14)
                .cardSurface()

                if let lastCheckInLine {
                    Text(lastCheckInLine).font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                }

                PrimaryButton(title: "Save check-in") { onSave(weightKg); dismiss() }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Bodyweight check-in")
            .navigationBarTitleDisplayMode(.inline)
            .hideKeyboardOnTap()
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func step(_ direction: Double) {
        weightKg = Self.rangeKg.clamped(weightKg + direction * Formulas.bodyweightStepKg(units: units))
    }
}

private extension ClosedRange<Double> {
    func clamped(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
