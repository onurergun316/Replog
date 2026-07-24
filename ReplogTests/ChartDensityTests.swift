//
//  ChartDensityTests.swift
//  ReplogTests
//
//  The ladder that decides how much chart a given amount of data has earned, and the
//  axis rules that stop a flat series reading as a cliff.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ChartDensityTests {

    // MARK: - Tiers

    @Test func tiersSplitAtOneTwoAndFive() {
        #expect(ChartDensity.of(0) == .none)
        #expect(ChartDensity.of(1) == .single)
        #expect(ChartDensity.of(2) == .sparse(2))
        #expect(ChartDensity.of(4) == .sparse(4))
        #expect(ChartDensity.of(5) == .full(5))
        #expect(ChartDensity.of(-3) == .none)      // never traps on a bad count
    }

    @Test func aLineIsNeverDrawnThroughOnePoint() {
        // The whole reason the per-exercise chart rendered blank: a LineMark with a
        // single point paints nothing at all.
        #expect(!ChartDensity.of(0).allowsLine)
        #expect(!ChartDensity.of(1).allowsLine)
        #expect(ChartDensity.of(2).allowsLine)
    }

    @Test func axesAndDirectLabelsSwapOver() {
        // Two marks are labelled directly; three earn an axis to read against.
        #expect(ChartDensity.of(1).labelsMarksDirectly)
        #expect(ChartDensity.of(2).labelsMarksDirectly)
        #expect(!ChartDensity.of(3).labelsMarksDirectly)
        #expect(!ChartDensity.of(2).showsAxis)
        #expect(ChartDensity.of(3).showsAxis)
    }

    @Test func trendLanguageAndSmoothingNeedRealEvidence() {
        // "Trend" is a claim about direction; two points cannot support one.
        #expect(!ChartDensity.of(4).allowsTrendLanguage)
        #expect(ChartDensity.of(5).allowsTrendLanguage)
        // Smoothing invents curvature that is not in sparse data.
        #expect(!ChartDensity.of(7).allowsSmoothing)
        #expect(ChartDensity.of(8).allowsSmoothing)
    }

    @Test func symbolsStayVisibleUntilTheLineIsDense() {
        #expect(ChartDensity.of(3).showsSymbols)
        #expect(ChartDensity.of(11).showsSymbols)
        #expect(!ChartDensity.of(12).showsSymbols)
    }

    @Test func cardHeightGrowsWithTheData() {
        // A card must not reserve 200pt to hold one bar — that is what reads as a
        // rendering failure rather than as "you have one session".
        #expect(ChartDensity.of(0).chartHeight == 0)
        #expect(ChartDensity.of(1).chartHeight == 96)
        #expect(ChartDensity.of(3).chartHeight == 140)
        #expect(ChartDensity.of(9).chartHeight == 180)
        let heights = [0, 1, 2, 3, 4, 5, 20].map { ChartDensity.of($0).chartHeight }
        #expect(heights == heights.sorted())          // monotonic, never shrinks
    }

    // MARK: - Axis domains

    @Test func aFlatSeriesGetsAMinimumSpan() {
        // Two bodyweight readings 0.3 kg apart: fitted to the data the axis turns normal
        // daily fluctuation into a cliff.
        let domain = ChartScales.yDomain(min: 93.9, max: 94.2,
                                         minSpan: ChartScales.bodyweightMinSpanKg)
        #expect(domain.upperBound - domain.lowerBound == 4)
        // Centred on the readings, so the line sits mid-card rather than at an edge.
        #expect(abs((domain.lowerBound + domain.upperBound) / 2 - 94.05) < 0.0001)
    }

    @Test func aWideSeriesIsPaddedNotForced() {
        let domain = ChartScales.yDomain(min: 80, max: 100, minSpan: 4)
        #expect(domain.lowerBound == 78)              // 10% of the 20 kg span
        #expect(domain.upperBound == 102)
    }

    @Test func aSinglePointStillProducesAUsableDomain() {
        let domain = ChartScales.yDomain(min: 94, max: 94, minSpan: 4)
        #expect(domain.upperBound - domain.lowerBound == 4)
    }

    @Test func e1rmSpanScalesWithTheLift() {
        // A 2.5 kg PR on a 200 kg deadlift must not fill the card the way it would on
        // a 20 kg curl.
        #expect(ChartScales.e1rmMinSpan(best: 40) == 10)      // floor holds for light lifts
        #expect(ChartScales.e1rmMinSpan(best: 200) == 30)     // 15% for heavy ones
    }
}
