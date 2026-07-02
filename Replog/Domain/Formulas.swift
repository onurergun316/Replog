//
//  Formulas.swift
//  Replog
//
//  Pure training math: estimated 1RM, unit conversion, and stepper increments.
//  All weights are stored in kg; display conversion happens at the edge.
//

import Foundation

enum Formulas {

    /// Epley estimated one-rep max: `weight * (1 + reps/30)`.
    /// A single rep returns the weight itself.
    static func e1rm(kg: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        return kg * (1 + Double(reps) / 30)
    }

    /// Integer estimated 1RM for display/storage.
    static func e1rmRounded(kg: Double, reps: Int) -> Int {
        Int(e1rm(kg: kg, reps: reps).rounded())
    }

    /// Converts kg to lb, rounded to the nearest 5 lb (matches the +5 lb stepper).
    static func kgToLb(_ kg: Double) -> Double {
        let lb = kg * 2.20462
        return (lb / 5).rounded() * 5
    }

    /// Converts a nearest-5 lb value back to kg (for editing in lb).
    static func lbToKg(_ lb: Double) -> Double {
        lb / 2.20462
    }

    /// Stepper increment for weight in the user's display unit, expressed in kg.
    /// +2.5 kg when displaying kg; +5 lb (≈2.2679 kg) when displaying lb.
    static func weightStepKg(units: Units) -> Double {
        switch units {
        case .kg: return 2.5
        case .lb: return lbToKg(5)
        }
    }

    /// The displayed weight value for a kg amount in the chosen units.
    static func displayWeight(kg: Double, units: Units) -> Double {
        switch units {
        case .kg: return kg
        case .lb: return kgToLb(kg)
        }
    }

    /// Formats a weight for display, dropping a trailing ".0" and appending the unit.
    static func formatWeight(kg: Double, units: Units, includeUnit: Bool = true) -> String {
        let value = displayWeight(kg: kg, units: units)
        let text: String = value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
        return includeUnit ? "\(text)\(units.label)" : text
    }

    // MARK: Bodyweight
    // Bar-weight display rounds lb to the nearest 5 (plate math); bodyweight needs the
    // scale's own resolution, so these convert at 0.1 precision instead.

    /// The displayed bodyweight for a kg amount, at 0.1 precision in either unit.
    static func displayBodyweight(kg: Double, units: Units) -> Double {
        let value = units == .kg ? kg : kg * 2.20462
        return (value * 10).rounded() / 10
    }

    /// Formats a bodyweight for display, dropping a trailing ".0" and appending the unit.
    static func formatBodyweight(kg: Double, units: Units, includeUnit: Bool = true) -> String {
        let value = displayBodyweight(kg: kg, units: units)
        let text: String = value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
        return includeUnit ? "\(text)\(units.label)" : text
    }

    /// Check-in stepper increment expressed in kg: ±0.5 kg, or ±1 lb when displaying lb.
    static func bodyweightStepKg(units: Units) -> Double {
        switch units {
        case .kg: return 0.5
        case .lb: return lbToKg(1)
        }
    }

    /// Parses user-typed weight text (entered in `units`) into clamped kilograms.
    /// Accepts "," or "." decimals; returns nil when the text isn't a number.
    static func parseWeightKg(_ raw: String, units: Units) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized) else { return nil }
        let kg = units == .kg ? value : lbToKg(value)
        return max(0, kg)
    }

    /// Parses user-typed reps text into a clamped positive integer (nil if non-numeric).
    static func parseReps(_ raw: String) -> Int? {
        guard let value = Int(raw.filter(\.isNumber)) else { return nil }
        return max(1, value)
    }
}
