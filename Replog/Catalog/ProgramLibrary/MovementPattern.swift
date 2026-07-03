//
//  MovementPattern.swift
//  Replog
//
//  The movement pattern a program slot prescribes (e.g. "squat", "horizontal_push").
//  Patterns are the abstraction the program library uses instead of naming a specific
//  exercise, so the planner can pick a concrete catalog movement that fits the pattern,
//  the user's equipment, and their history. Decodes leniently: any value not in the
//  known set survives as `.other(rawValue)` rather than failing the whole library.
//

import Foundation

/// A movement pattern prescribed by a program slot. `.other` preserves unknown/future
/// values verbatim so a new pattern upstream never breaks decoding.
nonisolated enum MovementPattern: Equatable, Hashable, Sendable {
    case squat, hinge, lunge
    case horizontalPush, verticalPush, horizontalPull, verticalPull
    case carry, coreBrace, coreFlexion
    case isolationArms, isolationCalves, isolationGlutes, isolationShoulders
    case plyometric
    case run, bike, rowErg, swim
    case stretchStatic, stretchDynamic, mobilityDrill
    case other(String)

    /// The known cases, excluding `.other`, in a stable order — handy for tests & mapping.
    static let known: [MovementPattern] = [
        .squat, .hinge, .lunge,
        .horizontalPush, .verticalPush, .horizontalPull, .verticalPull,
        .carry, .coreBrace, .coreFlexion,
        .isolationArms, .isolationCalves, .isolationGlutes, .isolationShoulders,
        .plyometric,
        .run, .bike, .rowErg, .swim,
        .stretchStatic, .stretchDynamic, .mobilityDrill,
    ]

    /// The snake_case token used in `programs.json` (round-trips through `init(raw:)`).
    var rawValue: String {
        switch self {
        case .squat: return "squat"
        case .hinge: return "hinge"
        case .lunge: return "lunge"
        case .horizontalPush: return "horizontal_push"
        case .verticalPush: return "vertical_push"
        case .horizontalPull: return "horizontal_pull"
        case .verticalPull: return "vertical_pull"
        case .carry: return "carry"
        case .coreBrace: return "core_brace"
        case .coreFlexion: return "core_flexion"
        case .isolationArms: return "isolation_arms"
        case .isolationCalves: return "isolation_calves"
        case .isolationGlutes: return "isolation_glutes"
        case .isolationShoulders: return "isolation_shoulders"
        case .plyometric: return "plyometric"
        case .run: return "run"
        case .bike: return "bike"
        case .rowErg: return "row_erg"
        case .swim: return "swim"
        case .stretchStatic: return "stretch_static"
        case .stretchDynamic: return "stretch_dynamic"
        case .mobilityDrill: return "mobility_drill"
        case .other(let raw): return raw
        }
    }

    /// Parses a raw token, folding case/whitespace. Unknown values become `.other`.
    init(raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = Self.known.first(where: { $0.rawValue == key }) {
            self = match
        } else {
            self = .other(key.isEmpty ? raw : key)
        }
    }

    /// Human-facing label, e.g. "Horizontal Push".
    var displayName: String {
        switch self {
        case .rowErg: return "Row (Erg)"
        case .other(let raw):
            return raw.split(whereSeparator: { $0 == "_" || $0 == " " })
                .map(\.capitalized).joined(separator: " ")
        default:
            return rawValue.split(separator: "_").map(\.capitalized).joined(separator: " ")
        }
    }

    /// True for the pure conditioning / mobility patterns that aren't loadable strength lifts.
    /// Used by the planner to decide whether a slot maps to a weighted movement at all.
    var isConditioningOrMobility: Bool {
        switch self {
        case .run, .bike, .rowErg, .swim,
             .stretchStatic, .stretchDynamic, .mobilityDrill:
            return true
        default:
            return false
        }
    }
}

extension MovementPattern: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(raw: raw)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
