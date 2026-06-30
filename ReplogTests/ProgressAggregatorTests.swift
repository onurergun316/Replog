//
//  ProgressAggregatorTests.swift
//  ReplogTests
//

import Testing
import Foundation
@testable import Replog

struct ProgressAggregatorTests {

    private func entry(_ e1rm: Int, daysAgo: Int) -> HistoryEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return HistoryEntry(exId: "X", date: date, topW: 100, topR: 5, e1rm: e1rm, sets: [])
    }

    @Test func summarizesBestCurrentAndTrend() {
        // Oldest -> newest e1RM: 100, 120, 110
        let history = [entry(100, daysAgo: 20), entry(120, daysAgo: 10), entry(110, daysAgo: 1)]
        let p = ProgressAggregator.summarize(exId: "X", history: history)
        #expect(p.bestE1rm == 120)
        #expect(p.currentE1rm == 110)            // latest by date
        #expect(p.series == [100, 120, 110])     // sorted oldest->newest
        #expect(p.sessionCount == 3)
        // 110 vs prior 120 = -8.33%
        #expect(p.trendPercent != nil)
        #expect(p.trend == .down)
    }

    @Test func sortsUnorderedHistory() {
        let history = [entry(110, daysAgo: 1), entry(100, daysAgo: 20), entry(120, daysAgo: 10)]
        let p = ProgressAggregator.summarize(exId: "X", history: history)
        #expect(p.series == [100, 120, 110])
    }

    @Test func singleSessionHasNoTrend() {
        let p = ProgressAggregator.summarize(exId: "X", history: [entry(100, daysAgo: 1)])
        #expect(p.trendPercent == nil)
        #expect(p.trend == .none)
        #expect(p.currentE1rm == 100)
    }

    @Test func emptyHistoryIsEmpty() {
        let p = ProgressAggregator.summarize(exId: "X", history: [])
        #expect(!p.hasData)
        #expect(p.bestE1rm == 0)
        #expect(p.series.isEmpty)
    }
}
