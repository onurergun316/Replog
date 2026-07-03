//
//  ReadinessModulator.swift
//  Replog
//
//  Optional subjective readiness at session start: three one-tap ratings (sleep, soreness,
//  stress) map to a session modulation — train as planned, cap intensity with a note, or trim
//  the last set of each exercise — with a plain-language reason surfaced on the session and in
//  the coach's suggestion ("eased off today — you reported poor sleep"). Also detects recurring
//  patterns across the week (e.g. three low-sleep days) for the coach. All pure & unit-tested;
//  the actual set-trimming applies to the built `ActiveSession`.
//

import Foundation

/// A single readiness dimension's rating. Higher = worse (more fatigue signal).
enum ReadinessRating: Int, Codable, CaseIterable, Sendable {
    case good = 0
    case moderate = 1
    case poor = 2
}

/// One readiness check-in: the three ratings the athlete tapped.
struct ReadinessCheckIn: Equatable, Sendable {
    var sleep: ReadinessRating
    var soreness: ReadinessRating
    var stress: ReadinessRating

    /// Combined fatigue load, 0 (fully fresh) … 6 (maximally taxed).
    var load: Int { sleep.rawValue + soreness.rawValue + stress.rawValue }

    static let fresh = ReadinessCheckIn(sleep: .good, soreness: .good, stress: .good)
}

/// How a session is adjusted for readiness.
enum SessionModulation: Equatable, Sendable {
    /// Train exactly as planned.
    case normal
    /// Keep the planned volume but flag "cap the intensity today" (a note only).
    case capIntensity
    /// Drop the last working set of each exercise to shed volume.
    case trimLastSet

    /// Whether this modulation removes any prescribed volume.
    var reducesVolume: Bool { self == .trimLastSet }
}

/// A recurring readiness pattern across the trailing week, for the coach to surface.
enum ReadinessPattern: Equatable, Sendable {
    case lowSleep(days: Int)
    case highSoreness(days: Int)
    case highStress(days: Int)

    var days: Int {
        switch self {
        case .lowSleep(let d), .highSoreness(let d), .highStress(let d): return d
        }
    }
}

enum ReadinessModulator {

    /// Load at or above which the last set is trimmed.
    static let trimThreshold = 4
    /// Load at or above which intensity is capped (but volume kept).
    static let capThreshold = 2
    /// Occurrences of a poor rating within the window that constitute a pattern.
    static let patternThreshold = 3
    /// The trailing window (days) patterns are detected over.
    static let patternWindowDays = 7

    // MARK: - Modulation

    /// Maps a check-in to a session modulation. Higher combined fatigue → more conservative.
    static func modulation(for checkIn: ReadinessCheckIn) -> SessionModulation {
        if checkIn.load >= trimThreshold { return .trimLastSet }
        if checkIn.load >= capThreshold { return .capIntensity }
        return .normal
    }

    /// A plain-language reason for the modulation, naming the flagged dimensions. Empty when
    /// the modulation is `.normal` (nothing to explain).
    static func reason(for checkIn: ReadinessCheckIn, modulation: SessionModulation) -> String {
        guard modulation != .normal else { return "" }
        let flags = flaggedDimensions(checkIn)
        guard !flags.isEmpty else {
            return modulation == .trimLastSet
                ? "Eased off today to help you recover."
                : "Capped intensity today to help you recover."
        }
        let verb = modulation == .trimLastSet ? "Trimmed a set" : "Capped intensity"
        return "\(verb) today — you reported \(list(flags))."
    }

    /// The human-named dimensions worth calling out (poor first, then moderate).
    private static func flaggedDimensions(_ c: ReadinessCheckIn) -> [String] {
        var out: [String] = []
        func add(_ rating: ReadinessRating, poor: String, moderate: String) {
            if rating == .poor { out.append(poor) }
            else if rating == .moderate { out.append(moderate) }
        }
        // Poor ratings first so the reason leads with the strongest signal.
        for wantPoor in [true, false] {
            if (c.sleep == .poor) == wantPoor { add(c.sleep, poor: "poor sleep", moderate: "so-so sleep") }
            if (c.soreness == .poor) == wantPoor { add(c.soreness, poor: "high soreness", moderate: "some soreness") }
            if (c.stress == .poor) == wantPoor { add(c.stress, poor: "high stress", moderate: "some stress") }
        }
        // De-dup while preserving order (a dimension is only added once by rating above).
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    // MARK: - Pattern detection

    /// The dominant readiness pattern within the trailing window, if a dimension was rated
    /// poor on at least `patternThreshold` distinct days. Nil when nothing recurs.
    static func recentPattern(ratings: [ReadinessCheckIn], forDates dates: [Date],
                              now: Date = Date(), calendar: Calendar = .current) -> ReadinessPattern? {
        precondition(ratings.count == dates.count)
        let cutoff = calendar.date(byAdding: .day, value: -patternWindowDays, to: now) ?? now
        var poorSleepDays = Set<Date>()
        var poorSorenessDays = Set<Date>()
        var poorStressDays = Set<Date>()
        for (checkIn, date) in zip(ratings, dates) where date >= cutoff {
            let day = calendar.startOfDay(for: date)
            if checkIn.sleep == .poor { poorSleepDays.insert(day) }
            if checkIn.soreness == .poor { poorSorenessDays.insert(day) }
            if checkIn.stress == .poor { poorStressDays.insert(day) }
        }
        // Surface the strongest (most days) pattern that clears the threshold.
        let candidates: [ReadinessPattern] = [
            .lowSleep(days: poorSleepDays.count),
            .highSoreness(days: poorSorenessDays.count),
            .highStress(days: poorStressDays.count),
        ].filter { $0.days >= patternThreshold }
        return candidates.max { $0.days < $1.days }
    }
}
