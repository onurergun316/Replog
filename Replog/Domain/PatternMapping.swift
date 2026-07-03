//
//  PatternMapping.swift
//  Replog
//
//  Maps a program's abstract `MovementPattern` onto concrete catalog facets (category,
//  force, mechanic, priority muscles, and name keywords) so a slot can be resolved to real
//  catalog exercises the athlete can actually perform. Pure and fully unit-tested: every
//  `MovementPattern` yields a mapping, and candidate selection honours equipment/injuries.
//
//  This is the bridge between Phase 1's program schema and the existing exercise catalog.
//

import Foundation

/// The catalog facets a movement pattern resolves to.
struct PatternFacets: Equatable, Sendable {
    /// Preferred catalog category (strength for lifts, stretching/plyometrics/cardio for the
    /// conditioning & mobility patterns). `nil` means "don't filter on category".
    var category: ExerciseCategory?
    /// Preferred force vector, used only to rank (never to exclude).
    var force: Force?
    /// Preferred mechanic, used only to rank (never to exclude).
    var mechanic: Mechanic?
    /// Priority muscles for the pattern, most important first. A strength pattern requires a
    /// candidate to train at least one of these as a primary mover.
    var muscles: [Muscle]
    /// Name keywords for patterns the catalog models by name rather than muscle (cardio).
    var nameKeywords: [String]
    /// Whether this is a conditioning/mobility pattern matched by category+name rather than by
    /// a primary-muscle requirement.
    var isConditioning: Bool
}

enum PatternMapping {

    /// The facets for a movement pattern. Total over `MovementPattern` — `.other` falls back
    /// to a general full-body strength mapping so an unknown slot still resolves to something.
    static func facets(for pattern: MovementPattern) -> PatternFacets {
        switch pattern {
        case .squat:
            return PatternFacets(category: .strength, force: .push, mechanic: .compound,
                                 muscles: [.quadriceps, .glutes, .hamstrings], nameKeywords: [], isConditioning: false)
        case .hinge:
            return PatternFacets(category: .strength, force: .pull, mechanic: .compound,
                                 muscles: [.hamstrings, .glutes, .lowerBack], nameKeywords: [], isConditioning: false)
        case .lunge:
            return PatternFacets(category: .strength, force: .push, mechanic: .compound,
                                 muscles: [.quadriceps, .glutes, .hamstrings], nameKeywords: [], isConditioning: false)
        case .horizontalPush:
            return PatternFacets(category: .strength, force: .push, mechanic: .compound,
                                 muscles: [.chest, .triceps, .shoulders], nameKeywords: [], isConditioning: false)
        case .verticalPush:
            return PatternFacets(category: .strength, force: .push, mechanic: .compound,
                                 muscles: [.shoulders, .triceps], nameKeywords: [], isConditioning: false)
        case .horizontalPull:
            return PatternFacets(category: .strength, force: .pull, mechanic: .compound,
                                 muscles: [.middleBack, .lats, .biceps], nameKeywords: [], isConditioning: false)
        case .verticalPull:
            return PatternFacets(category: .strength, force: .pull, mechanic: .compound,
                                 muscles: [.lats, .biceps, .middleBack], nameKeywords: [], isConditioning: false)
        case .carry:
            return PatternFacets(category: .strength, force: .static, mechanic: .compound,
                                 muscles: [.forearms, .traps, .abdominals], nameKeywords: [], isConditioning: false)
        case .coreBrace:
            return PatternFacets(category: .strength, force: .static, mechanic: .isolation,
                                 muscles: [.abdominals], nameKeywords: [], isConditioning: false)
        case .coreFlexion:
            return PatternFacets(category: .strength, force: .pull, mechanic: .isolation,
                                 muscles: [.abdominals], nameKeywords: [], isConditioning: false)
        case .isolationArms:
            return PatternFacets(category: .strength, force: nil, mechanic: .isolation,
                                 muscles: [.biceps, .triceps, .forearms], nameKeywords: [], isConditioning: false)
        case .isolationCalves:
            return PatternFacets(category: .strength, force: nil, mechanic: .isolation,
                                 muscles: [.calves], nameKeywords: [], isConditioning: false)
        case .isolationGlutes:
            return PatternFacets(category: .strength, force: nil, mechanic: .isolation,
                                 muscles: [.glutes], nameKeywords: [], isConditioning: false)
        case .isolationShoulders:
            return PatternFacets(category: .strength, force: nil, mechanic: .isolation,
                                 muscles: [.shoulders], nameKeywords: [], isConditioning: false)
        case .plyometric:
            return PatternFacets(category: .plyometrics, force: nil, mechanic: nil,
                                 muscles: [.quadriceps, .calves, .glutes], nameKeywords: [], isConditioning: true)
        case .run:
            return PatternFacets(category: .cardio, force: nil, mechanic: nil,
                                 muscles: [.quadriceps, .hamstrings, .calves],
                                 nameKeywords: ["run", "jog", "sprint", "treadmill"], isConditioning: true)
        case .bike:
            return PatternFacets(category: .cardio, force: nil, mechanic: nil,
                                 muscles: [.quadriceps, .glutes],
                                 nameKeywords: ["bike", "bicycl", "cycl", "elliptical"], isConditioning: true)
        case .rowErg:
            return PatternFacets(category: .cardio, force: nil, mechanic: nil,
                                 muscles: [.lats, .middleBack, .quadriceps],
                                 nameKeywords: ["row"], isConditioning: true)
        case .swim:
            return PatternFacets(category: .cardio, force: nil, mechanic: nil,
                                 muscles: [.lats, .shoulders],
                                 nameKeywords: ["swim"], isConditioning: true)
        case .stretchStatic:
            return PatternFacets(category: .stretching, force: .static, mechanic: nil,
                                 muscles: [], nameKeywords: [], isConditioning: true)
        case .stretchDynamic:
            return PatternFacets(category: .stretching, force: nil, mechanic: nil,
                                 muscles: [], nameKeywords: [], isConditioning: true)
        case .mobilityDrill:
            return PatternFacets(category: .stretching, force: nil, mechanic: nil,
                                 muscles: [], nameKeywords: [], isConditioning: true)
        case .other:
            // Unknown pattern → general compound strength, so the slot still resolves.
            return PatternFacets(category: .strength, force: nil, mechanic: .compound,
                                 muscles: [.chest, .lats, .quadriceps, .shoulders, .glutes],
                                 nameKeywords: [], isConditioning: false)
        }
    }

    /// Real catalog exercises that fit a program slot's pattern for the athlete, best first.
    /// Honors the app's "missing equipment counts as bodyweight" convention and drops any
    /// exercise whose primary mover is an injury-avoided muscle. `slotMuscles` (the program
    /// author's `primaryMuscles` for the slot) refine and re-rank the pattern's defaults.
    static func candidates(for pattern: MovementPattern,
                           slotMuscles: [Muscle] = [],
                           allowedEquipment: Set<Equipment>,
                           avoidMuscles: Set<Muscle> = [],
                           in catalog: ExerciseCatalog,
                           limit: Int = 12) -> [Exercise] {
        let facets = self.facets(for: pattern)
        // The muscles that matter: the slot's authored muscles first, then the pattern defaults.
        let wanted = orderedUnique(slotMuscles + facets.muscles)

        let filtered = catalog.all.filter { ex in
            // Equipment: nil equipment counts as bodyweight (allowed for everyone).
            guard allowedEquipment.contains(ex.equipment ?? .bodyOnly) else { return false }
            // Never load an injury-avoided region as a primary mover.
            if !avoidMuscles.isEmpty, ex.primaryMuscles.contains(where: avoidMuscles.contains) { return false }
            // Category gate when the pattern specifies one.
            if let cat = facets.category, ex.category != cat { return false }

            if facets.isConditioning {
                // Conditioning/mobility: match by name keyword when present, else accept the
                // whole category (e.g. any stretch for a stretch slot).
                guard !facets.nameKeywords.isEmpty else { return true }
                return facets.nameKeywords.contains { ex.name.lowercased().contains($0) }
            } else {
                // Strength: must train one of the wanted muscles as a PRIMARY mover.
                return ex.primaryMuscles.contains { wanted.contains($0) }
            }
        }

        return filtered
            .sorted { rank($0, facets: facets, wanted: wanted) < rank($1, facets: facets, wanted: wanted) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Ranking

    /// Lower is better. Prefers: trains a higher-priority wanted muscle, matches the pattern's
    /// mechanic, matches its force, then stable by name.
    private static func rank(_ ex: Exercise, facets: PatternFacets, wanted: [Muscle]) -> Int {
        var score = 0
        // Priority of the best wanted muscle this exercise trains as primary (0 = top).
        let muscleRank = ex.primaryMuscles.compactMap { wanted.firstIndex(of: $0) }.min() ?? wanted.count
        score += muscleRank * 100
        if let mech = facets.mechanic { score += ex.mechanic == mech ? 0 : 30 }
        if let force = facets.force { score += ex.force == force ? 0 : 10 }
        // Bias toward the plainest strength option for strength patterns.
        if !facets.isConditioning, ex.category != .strength { score += 5 }
        return score
    }

    private static func orderedUnique(_ muscles: [Muscle]) -> [Muscle] {
        var seen = Set<Muscle>()
        return muscles.filter { seen.insert($0).inserted }
    }
}
