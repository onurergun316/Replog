//
//  TrendCalculatorTests.swift
//  ReplogTests
//

import Testing
@testable import Replog

struct TrendCalculatorTests {

    @Test func trendDirections() {
        #expect(TrendCalculator.trend(current: 90, previous: 80) == .up)
        #expect(TrendCalculator.trend(current: 70, previous: 80) == .down)
        #expect(TrendCalculator.trend(current: 80, previous: 80) == .flat)
        #expect(TrendCalculator.trend(current: 80, previous: nil) == .none)
    }

    @Test func percentChange() {
        #expect(TrendCalculator.percentChange(current: 110, previous: 100) == 10)
        #expect(TrendCalculator.percentChange(current: 90, previous: 100) == -10)
        #expect(TrendCalculator.percentChange(current: 100, previous: nil) == nil)
        #expect(TrendCalculator.percentChange(current: 100, previous: 0) == nil)
    }

    @Test func trendColorsMapCorrectly() {
        #expect(Trend.up.color == .up)
        #expect(Trend.down.color == .down)
        #expect(Trend.flat.color == .text3)
    }
}
