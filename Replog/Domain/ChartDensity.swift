//
//  ChartDensity.swift
//  Replog
//
//  How much chart a given number of data points has earned.
//
//  A count is meaningful on session one. A rate, a share, a delta and a trend are not —
//  they need a denominator. Drawing them anyway is what made the Progress tab look
//  broken to a new athlete: a line through one point, an average over one week that
//  equalled the total, a share of 100%.
//
//  Every Progress card switches on this rather than inventing its own threshold, so the
//  ladder is one tested decision instead of a dozen scattered ones.
//

import Foundation

enum ChartDensity: Equatable {
    /// Nothing logged — replace the chart with a typed empty state, never draw an axis.
    case none
    /// One mark. Bars can show it; lines cannot, and state the value in words instead.
    case single
    /// 2–4 marks: a reduced chart, no axes, symbols always visible.
    case sparse(Int)
    /// 5+ marks: the chart as designed.
    case full(Int)

    static func of(_ count: Int) -> ChartDensity {
        switch count {
        case ..<1: return .none
        case 1: return .single
        case 2...4: return .sparse(count)
        default: return .full(count)
        }
    }

    var count: Int {
        switch self {
        case .none: return 0
        case .single: return 1
        case .sparse(let n), .full(let n): return n
        }
    }

    /// Whether a line may be drawn at all. One point is not a line.
    var allowsLine: Bool { count >= 2 }
    /// Axes only once there is enough shape to read against them.
    var showsAxis: Bool { count >= 3 }
    /// Each mark labelled directly, instead of an axis, while the chart is small.
    var labelsMarksDirectly: Bool { count > 0 && count <= 2 }
    /// The word "trend" is a claim; it needs five points behind it.
    var allowsTrendLanguage: Bool { count >= 5 }
    /// Curve smoothing invents shape that isn't in sparse data.
    var allowsSmoothing: Bool { count >= 8 }
    /// Point symbols stay on until the line is dense enough to read on its own.
    var showsSymbols: Bool { count < 12 }

    /// Chart height in points — a card must not reserve 200pt to hold one bar.
    var chartHeight: CGFloat {
        switch count {
        case 0: return 0
        case 1, 2: return 96
        case 3, 4: return 140
        default: return 180
        }
    }
}

/// Axis-domain rules shared by every Progress chart.
enum ChartScales {

    /// Smallest span a bodyweight axis may show, in kg. Two readings 0.3 kg apart on an
    /// auto-fitted axis render normal daily fluctuation as a cliff.
    static let bodyweightMinSpanKg: Double = 4

    /// A padded domain that never collapses below `minSpan`, centred on the data.
    ///
    /// `.automatic(includesZero: false)` alone fits the axis to the data, so a flat
    /// series becomes a dramatic zigzag of rounding noise. Bars keep their zero baseline
    /// and never use this; lines always do.
    static func yDomain(min low: Double, max high: Double,
                        minSpan: Double, padding: Double = 0.1) -> ClosedRange<Double> {
        guard high >= low else { return low...low + minSpan }
        let span = high - low
        if span < minSpan {
            let midpoint = (high + low) / 2
            return (midpoint - minSpan / 2)...(midpoint + minSpan / 2)
        }
        let pad = span * padding
        return (low - pad)...(high + pad)
    }

    /// Minimum span for an estimated-1RM axis: never tighter than 10 kg, and never
    /// tighter than 15% of the best lift, so a 2.5 kg PR doesn't read as a doubling.
    static func e1rmMinSpan(best: Double) -> Double { Swift.max(10, best * 0.15) }
}
