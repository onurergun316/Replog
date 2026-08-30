//
//  WorkoutProgram.swift
//  Replog
//
//  The value types for the bundled program library (`Resources/programs.json`), a curated
//  set of 62 structured training programs. Read-only reference data, like `Exercise` — user
//  data references a program by its `id` (stored on `Plan.programId`).
//
//  Decoding is lenient in the same spirit as `Exercise`: only `id` and `name` are truly
//  required; every other field falls back to a sensible default rather than failing the
//  whole library, and open-ended vocabularies (category, goals, experience level) stay as
//  raw strings so new values upstream never break the app. `MovementPattern` is the one
//  closed-ish enum, and it keeps unknowns via `.other`.
//

import Foundation

// MARK: - Sex focus

/// The sex a program is designed around. Never used as a hard gate — `female`/`*_focused`
/// programs remain available to everyone and only influence ranking (see `ProgramMatcher`).
nonisolated enum ProgramSex: Equatable, Sendable {
    case any
    case female
    case femaleFocused
    case maleFocused
    case other(String)

    var rawValue: String {
        switch self {
        case .any: return "any"
        case .female: return "female"
        case .femaleFocused: return "female_focused"
        case .maleFocused: return "male_focused"
        case .other(let raw): return raw
        }
    }

    init(raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "any", "": self = .any
        case "female": self = .female
        case "female_focused": self = .femaleFocused
        case "male_focused": self = .maleFocused
        case let other: self = .other(other)
        }
    }
}

extension ProgramSex: Codable {
    nonisolated init(from decoder: Decoder) throws {
        self.init(raw: try decoder.singleValueContainer().decode(String.self))
    }
    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Audience

/// Who a program targets. `ageRange` is `[min, max]` in the file; convenience accessors
/// expose the bounds and membership. `prerequisite`/`note` are optional free text.
nonisolated struct ProgramAudience: Equatable, Sendable, Codable {
    var sex: ProgramSex
    var experienceLevel: String
    var ageRange: [Int]
    var prerequisite: String?
    var note: String?

    var ageMin: Int? { ageRange.first }
    var ageMax: Int? { ageRange.count > 1 ? ageRange[1] : ageRange.first }

    /// Whether `age` falls inside the (inclusive) target range. A missing range accepts all.
    func admits(age: Int) -> Bool {
        guard let lo = ageMin, let hi = ageMax else { return true }
        return age >= min(lo, hi) && age <= max(lo, hi)
    }

    enum CodingKeys: String, CodingKey {
        case sex, experienceLevel, ageRange, prerequisite, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sex = (try? c.decodeIfPresent(ProgramSex.self, forKey: .sex)) ?? .any
        experienceLevel = (try? c.decodeIfPresent(String.self, forKey: .experienceLevel)) ?? "any"
        ageRange = (try? c.decodeIfPresent([Int].self, forKey: .ageRange)) ?? []
        prerequisite = try? c.decodeIfPresent(String.self, forKey: .prerequisite)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    init(sex: ProgramSex = .any, experienceLevel: String = "any", ageRange: [Int] = [],
         prerequisite: String? = nil, note: String? = nil) {
        self.sex = sex
        self.experienceLevel = experienceLevel
        self.ageRange = ageRange
        self.prerequisite = prerequisite
        self.note = note
    }
}

// MARK: - Slot / Day

/// One prescribed exercise-shaped slot within a program day: a movement pattern plus its
/// set/rep/intensity scheme. The concrete exercise is resolved later against the catalog.
/// `reps` stays a raw string ("5", "8-12", "30-60s", "3 min") — parsed downstream.
nonisolated struct ProgramSlot: Equatable, Sendable, Codable {
    var pattern: MovementPattern
    var variant: String?
    var primaryMuscles: [Muscle]
    var sets: Int
    var reps: String
    var intensity: String
    var restSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case pattern, variant, primaryMuscles, sets, reps, intensity, restSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = (try? c.decodeIfPresent(MovementPattern.self, forKey: .pattern)) ?? .other("")
        variant = try? c.decodeIfPresent(String.self, forKey: .variant)
        let rawMuscles = (try? c.decodeIfPresent([String].self, forKey: .primaryMuscles)) ?? []
        primaryMuscles = rawMuscles.compactMap { Muscle.lenient($0) }
        sets = (try? c.decodeIfPresent(Int.self, forKey: .sets)) ?? 0
        reps = (try? c.decodeIfPresent(String.self, forKey: .reps)) ?? ""
        intensity = (try? c.decodeIfPresent(String.self, forKey: .intensity)) ?? ""
        restSeconds = try? c.decodeIfPresent(Int.self, forKey: .restSeconds)
    }

    init(pattern: MovementPattern, variant: String? = nil, primaryMuscles: [Muscle] = [],
         sets: Int = 0, reps: String = "", intensity: String = "", restSeconds: Int? = nil) {
        self.pattern = pattern
        self.variant = variant
        self.primaryMuscles = primaryMuscles
        self.sets = sets
        self.reps = reps
        self.intensity = intensity
        self.restSeconds = restSeconds
    }
}

/// A named training day within a program (e.g. "Day A", "Push").
nonisolated struct ProgramDay: Equatable, Sendable, Codable {
    var name: String
    var slots: [ProgramSlot]

    enum CodingKeys: String, CodingKey { case name, slots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slots = (try? c.decodeIfPresent([ProgramSlot].self, forKey: .slots)) ?? []
    }

    init(name: String, slots: [ProgramSlot]) {
        self.name = name
        self.slots = slots
    }
}

// MARK: - Alternate schedule shapes

/// One week of a linear/couch-to-5k style plan that prescribes a whole session as prose.
nonisolated struct WeeklyStructureEntry: Equatable, Sendable, Codable {
    var week: Int
    var session: String

    enum CodingKeys: String, CodingKey { case week, session }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? 0
        session = (try? c.decodeIfPresent(String.self, forKey: .session)) ?? ""
    }

    init(week: Int, session: String) { self.week = week; self.session = session }
}

/// One week of a wave/5-3-1 style plan. The file stores this as an object keyed by
/// "week1"…"weekN"; we flatten it to a stable, label-sorted array.
nonisolated struct WaveWeek: Equatable, Sendable {
    var label: String
    var prescription: String
}

// MARK: - Progression

/// How a program advances load/volume over time, plus its deload rule. All free text —
/// the vocabulary is large and open-ended, so it's rendered, not switched on.
nonisolated struct ProgramProgression: Equatable, Sendable, Codable {
    var type: String
    var rule: String?
    var deload: String?

    enum CodingKeys: String, CodingKey { case type, rule, deload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "none"
        rule = try? c.decodeIfPresent(String.self, forKey: .rule)
        deload = try? c.decodeIfPresent(String.self, forKey: .deload)
    }

    init(type: String = "none", rule: String? = nil, deload: String? = nil) {
        self.type = type
        self.rule = rule
        self.deload = deload
    }
}

// MARK: - Program

/// A single curated training program from the bundled library.
nonisolated struct WorkoutProgram: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String
    let goals: [String]
    let sport: String?
    let audience: ProgramAudience
    let whoIsItFor: String
    let whoShouldAvoid: String
    let medicalDisclaimer: String?
    let daysPerWeek: Int
    let sessionMinutes: Int
    let durationWeeks: Int
    let equipmentRequired: [String]
    let equipmentOptional: [String]
    let location: [String]
    let days: [ProgramDay]
    let weeklyStructure: [WeeklyStructureEntry]
    let monthlyWave: [WaveWeek]
    let schedule: String
    let progression: ProgramProgression
    let scienceRationale: String
    /// Plain-language training principles the program rests on. Deliberately never a
    /// citation: the science informs the copy, it is not name-dropped at the athlete.
    let principles: [String]
    /// Whether this is a complete training plan in its own right.
    ///
    /// A few entries are adjuncts, not plans: a one-week deload, a stretching routine, a
    /// daily habit that says outright it "runs alongside any other plan", and the two
    /// return-to-training protocols that require clinician clearance. Recommending one as
    /// somebody's entire programme is a category error — a 12-week answer made of a
    /// one-week template. They stay browsable; they are just never auto-selected.
    /// Defaults to true, so a new program is a plan unless it says otherwise.
    let isStandalone: Bool
    let expectedResults: String
    let cautions: String
    let tags: [String]

    /// True when the program carries a medical disclaimer and must never be auto-selected
    /// without explicit user acknowledgement (see `ProgramMatcher` and program-detail UI).
    var requiresDisclaimerAcknowledgement: Bool {
        guard let d = medicalDisclaimer else { return false }
        return !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the program requires a prerequisite the matcher must verify against history.
    var prerequisite: String? {
        guard let p = audience.prerequisite?.trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty else { return nil }
        return p
    }
}

// MARK: - Lenient decoding

extension WorkoutProgram: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, category, goals, sport, audience, whoIsItFor, whoShouldAvoid
        case medicalDisclaimer, daysPerWeek, sessionMinutes, durationWeeks
        case equipmentRequired, equipmentOptional, location, days
        case weeklyStructure, monthlyWave, schedule, progression
        case scienceRationale, expectedResults, cautions, tags
        case principles = "evidence"
        case isStandalone = "standalone"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "general_fitness"
        goals = (try? c.decodeIfPresent([String].self, forKey: .goals)) ?? []
        sport = try? c.decodeIfPresent(String.self, forKey: .sport)
        audience = (try? c.decodeIfPresent(ProgramAudience.self, forKey: .audience)) ?? ProgramAudience()
        whoIsItFor = (try? c.decodeIfPresent(String.self, forKey: .whoIsItFor)) ?? ""
        whoShouldAvoid = (try? c.decodeIfPresent(String.self, forKey: .whoShouldAvoid)) ?? ""
        medicalDisclaimer = try? c.decodeIfPresent(String.self, forKey: .medicalDisclaimer)
        daysPerWeek = (try? c.decodeIfPresent(Int.self, forKey: .daysPerWeek)) ?? 0
        sessionMinutes = (try? c.decodeIfPresent(Int.self, forKey: .sessionMinutes)) ?? 0
        durationWeeks = (try? c.decodeIfPresent(Int.self, forKey: .durationWeeks)) ?? 0
        equipmentRequired = (try? c.decodeIfPresent([String].self, forKey: .equipmentRequired)) ?? []
        equipmentOptional = (try? c.decodeIfPresent([String].self, forKey: .equipmentOptional)) ?? []
        location = (try? c.decodeIfPresent([String].self, forKey: .location)) ?? []
        days = (try? c.decodeIfPresent([ProgramDay].self, forKey: .days)) ?? []
        weeklyStructure = (try? c.decodeIfPresent([WeeklyStructureEntry].self, forKey: .weeklyStructure)) ?? []
        monthlyWave = Self.decodeWave(from: c)
        schedule = (try? c.decodeIfPresent(String.self, forKey: .schedule)) ?? ""
        progression = (try? c.decodeIfPresent(ProgramProgression.self, forKey: .progression)) ?? ProgramProgression()
        scienceRationale = (try? c.decodeIfPresent(String.self, forKey: .scienceRationale)) ?? ""
        principles = (try? c.decodeIfPresent([String].self, forKey: .principles)) ?? []
        isStandalone = (try? c.decodeIfPresent(Bool.self, forKey: .isStandalone)) ?? true
        expectedResults = (try? c.decodeIfPresent(String.self, forKey: .expectedResults)) ?? ""
        cautions = (try? c.decodeIfPresent(String.self, forKey: .cautions)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }

    /// `monthlyWave` is an object ({"week1": "...", "week2": "..."}); flatten it into a
    /// stable array sorted by the numeric suffix of the key (week1 < week2 < week10).
    nonisolated private static func decodeWave(from c: KeyedDecodingContainer<CodingKeys>) -> [WaveWeek] {
        guard let wave = try? c.decodeIfPresent([String: String].self, forKey: .monthlyWave) else {
            return []
        }
        return wave
            .map { WaveWeek(label: $0.key, prescription: $0.value) }
            .sorted { Self.weekOrder($0.label) < Self.weekOrder($1.label) }
    }

    /// Numeric ordering key for a "weekN" label; non-numeric labels sort last, alphabetically.
    nonisolated private static func weekOrder(_ label: String) -> Int {
        let digits = label.filter(\.isNumber)
        return Int(digits) ?? Int.max
    }
}
