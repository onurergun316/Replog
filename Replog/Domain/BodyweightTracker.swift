//
//  BodyweightTracker.swift
//  Replog
//
//  Pure logic for the periodic bodyweight check-in: when the next check-in is due,
//  and the trend over the recent series (delta, weekly rate, direction). Storage is
//  `BodyweightEntry`; display conversion lives in `Formulas`.
//

import Foundation

/// A digest of the recent bodyweight series, ready for the Today card.
struct BodyweightSnapshot: Equatable, Sendable {
    /// The latest logged weight, in kg.
    var currentKg: Double
    /// When it was logged.
    var date: Date
    /// Change vs the previous check-in, in kg (nil for the first entry).
    var deltaKg: Double?
    /// Least-squares rate of change over the trailing window, in kg per week
    /// (nil until two check-ins land inside the window).
    var weeklyRateKg: Double?
    /// Direction of `weeklyRateKg` with a noise deadband (`.none` while rate is nil).
    var direction: Trend
    /// The recent series (oldest first) scaled for `Sparkline`'s integer values.
    var sparklineValues: [Int]
}

enum BodyweightTracker {

    /// Days between check-in prompts.
    static let checkInIntervalDays = 7
    /// Trailing window the weekly rate is fitted over.
    static let trendWindowDays = 28
    /// |rate| below this reads as scale noise, not a trend (kg per week).
    static let flatBandKgPerWeek = 0.15
    /// How many recent entries the sparkline shows.
    static let sparklinePoints = 12

    /// Whether the periodic check-in is due: no entry yet, or the last one is at least
    /// `checkInIntervalDays` calendar days old.
    static func checkInDue(lastDate: Date?, now: Date = Date(),
                           calendar: Calendar = .current) -> Bool {
        guard let lastDate else { return true }
        let from = calendar.startOfDay(for: lastDate)
        let to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return days >= checkInIntervalDays
    }

    /// Digests the series into the Today-card snapshot. Order-invariant; nil when empty.
    @MainActor
    static func snapshot(entries: [BodyweightEntry]) -> BodyweightSnapshot? {
        let sorted = entries.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }

        let previous = sorted.dropLast().last
        let rate = weeklyRate(sorted: sorted, anchoredAt: latest.date)

        return BodyweightSnapshot(
            currentKg: latest.weightKg,
            date: latest.date,
            deltaKg: previous.map { latest.weightKg - $0.weightKg },
            weeklyRateKg: rate,
            direction: direction(weeklyRateKg: rate),
            // 0.1 kg resolution — Sparkline normalises, so only relative shape matters.
            sparklineValues: sorted.suffix(sparklinePoints).map { Int(($0.weightKg * 10).rounded()) }
        )
    }

    /// Whether a trend direction moves toward (`true`), against (`false`), or neutrally
    /// (nil) with respect to the user's goal. Drives the card tint only — flat is always
    /// neutral, and recomp/sport have no "right" direction for the scale.
    static func isFavorable(_ direction: Trend, for goal: Goal) -> Bool? {
        switch (direction, goal) {
        case (.up, .buildMuscle): return true
        case (.up, .loseWeight): return false
        case (.down, .loseWeight): return true
        case (.down, .buildMuscle): return false
        default: return nil
        }
    }

    // MARK: - Internals

    /// Least-squares slope (kg/week) over entries within `trendWindowDays` of the anchor.
    @MainActor
    private static func weeklyRate(sorted: [BodyweightEntry], anchoredAt anchor: Date) -> Double? {
        let windowStart = anchor.addingTimeInterval(-Double(trendWindowDays) * 86_400)
        let window = sorted.filter { $0.date >= windowStart }
        guard window.count >= 2 else { return nil }

        let days = window.map { $0.date.timeIntervalSince(windowStart) / 86_400 }
        let weights = window.map(\.weightKg)
        let n = Double(window.count)
        let meanX = days.reduce(0.0, +) / n
        let meanY = weights.reduce(0.0, +) / n
        var covXY = 0.0
        var varX = 0.0
        for (x, y) in zip(days, weights) {
            covXY += (x - meanX) * (y - meanY)
            varX += (x - meanX) * (x - meanX)
        }
        // All entries on the same day (upsert makes this rare): no time spread, no rate.
        guard varX > 0 else { return nil }
        return covXY / varX * 7
    }

    private static func direction(weeklyRateKg: Double?) -> Trend {
        guard let rate = weeklyRateKg else { return .none }
        if rate > flatBandKgPerWeek { return .up }
        if rate < -flatBandKgPerWeek { return .down }
        return .flat
    }
}
