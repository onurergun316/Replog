//
//  RepScheme.swift
//  Replog
//
//  Parses a program slot's free-text `reps` and `intensity` strings into concrete
//  `SetTemplate` targets. The library authors reps as prose — "5", "8-12", "10/side",
//  "30-60s", "3 min", "1 min hard / 90s easy" — so the parser is deliberately lenient and
//  always returns a usable target. Pure & fully unit-tested.
//
//  Convention (also documented in ARCHITECTURE.md):
//   • A plain count or range → the range's LOWER bound (you start there and earn the top of
//     the range before adding load — the double-progression the library favours).
//   • A per-side scheme ("/side", "/leg", "each") → the per-side count, flagged `isPerSide`.
//   • A time/hold/interval scheme ("30-60s", "3 min", "45s") → the duration in SECONDS
//     (lower bound), stored in `reps` and flagged `isTimed`. SetTemplate has no duration
//     field, so timed slots encode seconds in `reps`; the UI can read `isTimed` to label it.
//   • Anything unparseable → a sensible default (10 reps).
//

import Foundation

/// A parsed rep target for one slot.
nonisolated struct RepTarget: Equatable, Sendable {
    /// Target repetitions, OR — when `isTimed` — the target duration in seconds.
    var reps: Int
    /// True when the value represents a time/hold in seconds rather than a repetition count.
    var isTimed: Bool
    /// True when the value is per side/leg/arm (the set is performed on each side).
    var isPerSide: Bool

    static let fallback = RepTarget(reps: 10, isTimed: false, isPerSide: false)
}

enum RepScheme {

    /// Minimum/maximum sensible values so a stray large number can't poison a template.
    private static let repBounds = 1...50
    private static let timeBounds = 1...600   // up to 10 minutes, in seconds

    /// Parses a slot's `reps` string into a `RepTarget`. `pattern` lets a distance be
    /// expressed as the time it takes — a 200 m swim is not a 200 m sprint.
    static func parse(reps raw: String, pattern: MovementPattern? = nil) -> RepTarget {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .fallback }

        let isPerSide = ["/side", "/leg", "/arm", "per side", "per leg", "each side",
                         "each leg", "each", "/direction", "/letter"].contains { s.contains($0) }

        // First number (or the lower bound of a leading range like "8-12" / "30-60").
        guard let first = firstNumber(in: s) else {
            return RepTarget(reps: RepTarget.fallback.reps, isTimed: false, isPerSide: isPerSide)
        }

        if let unit = timeUnit(in: s) {
            let seconds: Int
            switch unit {
            case .minutes: seconds = first * 60
            case .seconds: seconds = first
            case .metres:  seconds = Int((Double(first) * secondsPerMetre(for: pattern)).rounded())
            }
            return RepTarget(reps: clamp(seconds, timeBounds), isTimed: true, isPerSide: isPerSide)
        }
        return RepTarget(reps: clamp(first, repBounds), isTimed: false, isPerSide: isPerSide)
    }

    /// Parses an RPE from a slot's `intensity` string ("RPE 8", "RPE 7-8", "@8"), or nil.
    /// Ranges take the higher (harder) bound, matching how coaches cue an RPE ceiling.
    static func parseRPE(intensity raw: String) -> Int? {
        let s = raw.lowercased()
        guard let range = s.range(of: "rpe") else {
            // Bare "@8"/"@ 8" shorthand.
            if let at = s.range(of: "@"), let n = firstNumber(in: String(s[at.upperBound...])),
               (5...10).contains(n) { return n }
            return nil
        }
        let tail = String(s[range.upperBound...])
        let numbers = allNumbers(in: tail)
        guard let value = numbers.prefix(2).max() else { return nil }
        return (1...10).contains(value) ? value : nil
    }

    /// Builds the concrete set list for a slot: `sets` copies of the resolved rep target,
    /// with the given starting weight and a resolved RPE (parsed, else `defaultRPE`).
    /// `estimated` flags the weight as a computed first-session seed (see `StartingLoadEstimator`).
    static func sets(for slot: ProgramSlot, startingWeightKg: Double,
                     defaultRPE: Int = 8, estimated: Bool = false) -> [GeneratedSet] {
        let count = max(1, min(slot.sets, 8))
        let target = parse(reps: slot.reps, pattern: slot.pattern)
        let rpe = parseRPE(intensity: slot.intensity) ?? defaultRPE
        return Array(repeating: GeneratedSet(weightKg: startingWeightKg, reps: target.reps,
                                             rpe: rpe, estimated: estimated),
                     count: count)
    }

    /// The resolved (target reps, RPE) for a slot — used to compute a per-user starting load
    /// before building the sets. RPE parsed from intensity, else `defaultRPE`.
    static func target(for slot: ProgramSlot, defaultRPE: Int = 8) -> (reps: Int, rpe: Int, isTimed: Bool) {
        let parsed = parse(reps: slot.reps)
        return (parsed.reps, parseRPE(intensity: slot.intensity) ?? defaultRPE, parsed.isTimed)
    }

    // MARK: - Number & unit extraction

    private enum TimeUnit { case seconds, minutes, metres }

    /// Detects the unit attached to the first number ("30s", "30-60s", "3 min", "200m").
    ///
    /// A bare `m` is METRES. It used to be read as minutes, which turned a 20-metre farmer's
    /// carry into a 20-minute one, a 200-metre swim into 200 minutes, and a 20-metre sprint
    /// into a 10-minute sprint — all then clamped to the 600s ceiling, so 32 slots across the
    /// library reached the athlete's plan as ten-minute sets. Minutes must say "min".
    private static func timeUnit(in s: String) -> TimeUnit? {
        // The unit has to belong to the quantity we are actually prescribing — the first one.
        // Matching a unit ANYWHERE in the string made "6 x 30m shuttle, 20s between reps,
        // 3 min between sets" a six-MINUTE set, because the string mentions minutes at all.
        // And "10-12 or 30m" is a rep scheme with a distance alternative: the reps win.
        for unit in ["min", "sec", "s", "m"] where unitFollowsFirstQuantity(in: s, unit: unit) {
            switch unit {
            case "min":         return .minutes
            case "sec", "s":    return .seconds
            default:            return .metres
            }
        }
        return nil
    }

    /// How long a metre takes, by what the athlete is doing with it. A loaded carry is
    /// roughly 0.8 m/s; a sprint is not. Used to express a distance as the seconds it
    /// occupies, because `SetTemplate` stores no distance.
    static func secondsPerMetre(for pattern: MovementPattern?) -> Double {
        switch pattern {
        case .carry:                   return 1.25
        case .swim:                    return 1.5
        case .rowErg:                  return 0.35
        case .run:                     return 0.30
        case .plyometric:              return 0.20
        case .bike:                    return 0.10
        default:                       return 0.5
        }
    }

    /// True when `unit` trails the first QUANTITY — a number or a range like "30-60", whose
    /// unit is written once at the end.
    private static func unitFollowsFirstQuantity(in s: String, unit: String) -> Bool {
        let chars = Array(s)
        guard let start = chars.firstIndex(where: { $0.isNumber }) else { return false }
        var j = start
        while j < chars.count, chars[j].isNumber { j += 1 }
        // A range carries its unit after the upper bound: "30-60s", "8-12 min".
        if j < chars.count, chars[j] == "-" || chars[j] == "\u{2013}" {
            var k = j + 1
            while k < chars.count, chars[k].isNumber { k += 1 }
            if k > j + 1 { j = k }
        }
        while j < chars.count, chars[j] == " " { j += 1 }
        return matches(chars, at: j, unit: unit)
    }

    /// True if the string contains a digit immediately followed (allowing one space) by any
    /// of `units`. Avoids matching letters inside words.
    private static func rangeOfDigitThenUnit(in s: String, units: [String]) -> Bool {
        let chars = Array(s)
        for (i, c) in chars.enumerated() where c.isNumber {
            var j = i + 1
            while j < chars.count, chars[j] == " " { j += 1 }
            for unit in units {
                if matches(chars, at: j, unit: unit) { return true }
            }
        }
        return false
    }

    private static func matches(_ chars: [Character], at index: Int, unit: String) -> Bool {
        let u = Array(unit)
        guard index + u.count <= chars.count else { return false }
        for k in 0..<u.count where chars[index + k] != u[k] { return false }
        return true
    }

    /// The first integer appearing in the string, or nil.
    private static func firstNumber(in s: String) -> Int? {
        allNumbers(in: s).first
    }

    /// Every integer appearing in the string, in order.
    private static func allNumbers(in s: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        for c in s {
            if c.isNumber { current.append(c) }
            else if !current.isEmpty { result.append(Int(current) ?? 0); current = "" }
        }
        if !current.isEmpty { result.append(Int(current) ?? 0) }
        return result
    }

    private static func clamp(_ value: Int, _ bounds: ClosedRange<Int>) -> Int {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}
