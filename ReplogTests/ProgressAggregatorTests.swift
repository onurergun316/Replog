//
//  ProgressAggregatorTests.swift
//  ReplogTests
//
//  Summarizing one exercise's history. Fixtures vary the *top set*, not the stored
//  `e1rm` field: analytics recompute the estimate over effective load (so bodyweight
//  lifts score at all), which means a fixture that varied only the stored number would
//  describe behaviour the code no longer has.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ProgressAggregatorTests {

    private func entry(topW: Double, daysAgo: Int) -> HistoryEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return HistoryEntry(exId: "X", date: date, topW: topW, topR: 5,
                            e1rm: Formulas.e1rmRounded(kg: topW, reps: 5), sets: [])
    }

    /// The estimate a 5-rep top set at this weight produces.
    private func e1(_ topW: Double) -> Int { Formulas.e1rmRounded(kg: topW, reps: 5) }

    @Test func summarizesBestCurrentAndTrend() {
        // Oldest -> newest top set: 100, 120, 110 kg — improved, then backed off.
        let history = [entry(topW: 100, daysAgo: 20),
                       entry(topW: 120, daysAgo: 10),
                       entry(topW: 110, daysAgo: 1)]
        let p = ProgressAggregator.summarize(exId: "X", history: history)

        #expect(p.bestE1rm == e1(120))
        #expect(p.currentE1rm == e1(110))                       // latest by date, not best
        #expect(p.series == [e1(100), e1(120), e1(110)])        // sorted oldest -> newest
        #expect(p.sessionCount == 3)
        #expect(p.trendPercent != nil)
        #expect(p.trend == .down)                               // 110 kg after 120 kg
    }

    @Test func sortsUnorderedHistory() {
        let history = [entry(topW: 110, daysAgo: 1),
                       entry(topW: 100, daysAgo: 20),
                       entry(topW: 120, daysAgo: 10)]
        let p = ProgressAggregator.summarize(exId: "X", history: history)
        #expect(p.series == [e1(100), e1(120), e1(110)])
    }

    @Test func singleSessionHasNoTrend() {
        let p = ProgressAggregator.summarize(exId: "X", history: [entry(topW: 100, daysAgo: 1)])
        #expect(p.trendPercent == nil)
        #expect(p.trend == .none)
        #expect(p.currentE1rm == e1(100))
    }

    @Test func emptyHistoryIsEmpty() {
        let p = ProgressAggregator.summarize(exId: "X", history: [])
        #expect(!p.hasData)
        #expect(p.bestE1rm == 0)
        #expect(p.series.isEmpty)
    }

    @Test func aBodyweightLiftScoresOnceGivenAResolver() {
        // The reason the fixtures above stopped keying on the stored `e1rm`: with the
        // default resolver a pull-up's 0 kg top set scores zero, and with the live one
        // it scores its share of the athlete's bodyweight.
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let pullup = HistoryEntry(exId: "Pullups", date: date, topW: 0, topR: 10,
                                  e1rm: 0, sets: [RecordedSet(w: 0, r: 10)])
        let resolver = LoadResolver(exercise: { ExerciseCatalog.shared.exercise(id: $0) },
                                    bodyweight: BodyweightResolver(series: [(date, 80)]))

        #expect(ProgressAggregator.summarize(exId: "Pullups", history: [pullup]).bestE1rm == 0)
        #expect(ProgressAggregator.summarize(exId: "Pullups", history: [pullup],
                                             load: resolver).bestE1rm
                == Formulas.e1rmRounded(kg: 0.95 * 80, reps: 10))
    }
}
