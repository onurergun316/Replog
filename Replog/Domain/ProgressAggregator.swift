//
//  ProgressAggregator.swift
//  Replog
//
//  Turns an exercise's history into the numbers the Progress screens show:
//  best & current estimated 1RM, trend %, and a sparkline series.
//

import Foundation

struct ExerciseProgress: Equatable, Sendable {
    var exId: String
    var bestE1rm: Int
    var currentE1rm: Int
    /// Percent change of the latest session's e1RM vs the prior session, or nil.
    var trendPercent: Double?
    /// e1RM over time (oldest -> newest) for the chart/sparkline.
    var series: [Int]
    var sessionCount: Int

    var hasData: Bool { sessionCount > 0 }
    var trend: Trend {
        guard let trendPercent else { return .none }
        if trendPercent > 0 { return .up }
        if trendPercent < 0 { return .down }
        return .flat
    }
}

enum ProgressAggregator {
    /// Summarizes a single exercise's history (any order; sorted internally by date).
    ///
    /// `load` recomputes each session's estimated 1RM over *effective* load. The stored
    /// `e1rm` was written from the logged weight alone, which is zero for a bodyweight
    /// movement — so pull-ups and dips ranked at zero and never surfaced in Strength.
    static func summarize(exId: String, history: [HistoryEntry],
                          load: LoadResolver = .stored) -> ExerciseProgress {
        let sorted = history.sorted { $0.date < $1.date }
        let series = sorted.map { load.e1rm($0) }
        let best = series.max() ?? 0
        let current = series.last ?? 0
        let previous = series.count >= 2 ? series[series.count - 2] : nil
        let trend = TrendCalculator.percentChange(current: Double(current),
                                                  previous: previous.map(Double.init))
        return ExerciseProgress(
            exId: exId,
            bestE1rm: best,
            currentE1rm: current,
            trendPercent: trend,
            series: series,
            sessionCount: sorted.count
        )
    }
}
