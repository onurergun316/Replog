//
//  WeightComparison.swift
//  Replog
//
//  The things a lifted total can be measured against.
//
//  "You moved 6,074 kg" is a number nobody has a feel for. "That is three Smart cars" is a
//  picture. These are the bundled reference masses and animal strength figures that make
//  that translation possible, loaded from `comparisons.json`.
//
//  Lenient decoding throughout, like `Exercise` and `WorkoutProgram`: a malformed row is
//  skipped rather than taking the whole file down, because a missing fun fact must never
//  cost the athlete their session summary.
//

import Foundation

/// What kind of thing a comparison is, so copy can pick a register that fits.
nonisolated enum ComparisonFamily: String, Codable, Sendable, CaseIterable {
    /// Inanimate mass: vehicles, aircraft, machinery, landmarks.
    case object
    /// A living animal's body mass.
    case animal
    /// An animal's push/pull/lift force rather than its weight.
    case strength
}

/// How an animal's strength figure was arrived at. Surfaced so the app never presents a
/// viral claim as if it were a laboratory measurement.
nonisolated enum ComparisonConfidence: String, Codable, Sendable {
    case measured, estimated, popularClaim

    init(lenient raw: String) {
        switch raw.lowercased().replacingOccurrences(of: "-", with: "") {
        case "measured":  self = .measured
        case "estimated": self = .estimated
        default:          self = .popularClaim
        }
    }

    /// A hedge to attach to the claim, empty when the figure is solid.
    var hedge: String {
        switch self {
        case .measured:     return ""
        case .estimated:    return "roughly "
        case .popularClaim: return "reportedly "
        }
    }
}

/// Which way an animal produces force, so a pressing week is compared against animals
/// raising a load and a pulling week against animals hauling one.
nonisolated enum ComparisonMode: String, Codable, Sendable {
    case lift, pull, carry

    init?(lenient raw: String) {
        switch raw.lowercased() {
        case "lift":  self = .lift
        case "pull":  self = .pull
        case "carry": self = .carry
        // Bite force and anything else is not a training comparison at any scale.
        default:      return nil
        }
    }
}

/// What the figure actually is. The distinction matters: an ox "pulling 2,800 kg" is
/// dragging that mass on a sled, and the force it produces is a fraction of it. Treating
/// the two alike would tell an athlete their session equalled a fifth of an ox.
nonisolated enum ComparisonLoad: String, Codable, Sendable {
    /// A mass the animal genuinely raises or pulls with its own force.
    case lift
    /// A mass on a sled or cart. Phrased as a load being dragged, never as a lift.
    case sled

    init(lenient raw: String) {
        self = raw.lowercased() == "sled" ? .sled : .lift
    }
}

/// One thing a total can be compared against.
nonisolated struct WeightComparison: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// Natural singular with its article, e.g. "a city bus".
    var singular: String
    /// Natural plural without an article, e.g. "city buses".
    var plural: String
    /// The mass, or the force in kilogram-force for a `strength` entry.
    var kg: Double
    var family: ComparisonFamily
    /// Only meaningful for `strength`.
    var mode: ComparisonMode?
    /// Only meaningful for `strength`: whether the figure is force or a dragged sled load.
    var load: ComparisonLoad
    var confidence: ComparisonConfidence
    /// Why this figure was chosen, in editorial voice. Provenance for whoever revisits the
    /// data — not athlete-facing copy, and it must never name a paper if it becomes so.
    var note: String
    /// Where the figure came from. Provenance only: never rendered, so it may cite freely.
    var source: String

    /// "3 city buses" / "1 city bus" — the count already folded into the noun.
    func phrase(count: Int) -> String {
        count == 1 ? singular : "\(count) \(plural)"
    }
}

/// The decoded file: three lists, each optional so a partial file still loads.
nonisolated struct ComparisonLibrary: Decodable {
    var objects: [WeightComparison] = []
    var animals: [WeightComparison] = []
    var strength: [WeightComparison] = []

    enum CodingKeys: String, CodingKey { case objects, animals, strength }

    /// Memberwise construction for tests and the empty fallback.
    init(objects: [WeightComparison] = [], animals: [WeightComparison] = [],
         strength: [WeightComparison] = []) {
        self.objects = objects
        self.animals = animals
        self.strength = strength
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objects = (try? c.decodeIfPresent([LenientRow].self, forKey: .objects))?
            .compactMap { $0.comparison(family: .object) } ?? []
        animals = (try? c.decodeIfPresent([LenientRow].self, forKey: .animals))?
            .compactMap { $0.comparison(family: .animal) } ?? []
        strength = (try? c.decodeIfPresent([LenientRow].self, forKey: .strength))?
            .compactMap { $0.comparison(family: .strength) } ?? []
    }
}

/// A row exactly as written in the file, before validation.
private nonisolated struct LenientRow: Decodable {
    var id: String?
    var singular: String?
    var plural: String?
    var kg: Double?
    var forceKg: Double?
    var mode: String?
    var loadType: String?
    var confidence: String?
    var note: String?
    var source: String?

    /// A usable comparison, or nil when the row cannot carry its own weight: no id, no
    /// noun, or a mass of zero (which would divide a total into infinity).
    func comparison(family: ComparisonFamily) -> WeightComparison? {
        guard let id, !id.isEmpty,
              let singular, !singular.isEmpty,
              let mass = kg ?? forceKg, mass > 0 else { return nil }
        let parsedMode = mode.flatMap(ComparisonMode.init(lenient:))
        // A strength entry with no usable mode has nothing to say about training.
        if family == .strength, parsedMode == nil { return nil }
        return WeightComparison(
            id: id,
            singular: singular,
            plural: plural?.isEmpty == false ? plural! : singular,
            kg: mass,
            family: family,
            mode: parsedMode,
            load: ComparisonLoad(lenient: loadType ?? "lift"),
            confidence: ComparisonConfidence(lenient: confidence ?? "measured"),
            note: note ?? "",
            source: source ?? ""
        )
    }
}
