//
//  BodyweightLoad.swift
//  Replog
//
//  What fraction of your bodyweight a bodyweight movement actually loads.
//
//  A pull-up moves nearly all of you; a crunch lifts your head and shoulders. Logging
//  both as "0 kg" made every calisthenics set worth nothing — no tonnage, no estimated
//  1RM, no place in Strength or PRs. This table is how the app credits them honestly.
//
//  Grounded in force-plate ground-reaction-force work (Ebben et al. 2011, JSCR;
//  Gouvali & Boudolos 2005) and Dempster/de Leva segment masses — head+neck ~8% of
//  bodyweight, head-arms-trunk ~68%, both legs ~32%, shanks+feet ~12%, each arm ~5%.
//  Values deliberately err LOW, matching `StartingLoadEstimator`'s house philosophy:
//  under-crediting is a smaller lie than over-crediting.
//
//  See PROGRESS_DESIGN.md §3 for the full table and its citations.
//

import Foundation

enum BodyweightLoad {

    /// Seconds of tension counted as one rep-equivalent for a timed hold.
    static let secondsPerRepEquivalent: Double = 3

    // MARK: - Classification

    /// Whether this movement is loaded by the athlete's own bodyweight.
    ///
    /// Missing equipment counts as bodyweight — the same convention `PatternMapping`
    /// uses. Stretching and cardio are excluded: a hamstring stretch is not tonnage,
    /// and crediting it would inflate every total in the app. (That exclusion is not a
    /// rounding detail — it covers 85 of the catalog's 188 equipment-free entries.)
    ///
    /// `.other` is a grab-bag that holds two very different things: apparatus bodyweight
    /// movements — dips on bars, pull-up/chin variants, muscle-ups, rings, TRX/suspension,
    /// rope climbs, and the plyometric jumps/hops/sprints — sit right next to genuinely
    /// externally-loaded work (sled drags, plate raises, the trap-bar deadlift, sledgehammer
    /// swings). Without crediting the first group a parallel-bar dip or a pull-up counts as
    /// zero — exactly the calisthenics-is-worthless bug this file exists to fix — so `.other`
    /// is treated as bodyweight *unless* its name marks it as implement-loaded. A "weighted
    /// dip"/"weighted pull-up" stays bodyweight: its stored weight is added load on top of
    /// the bodyweight share, which is precisely what `effectiveKg` layers.
    static func isBodyweightLoaded(_ exercise: Exercise) -> Bool {
        switch exercise.category {
        case .strength, .plyometrics: break
        default: return false
        }
        switch exercise.equipment ?? .bodyOnly {
        case .bodyOnly:
            return true
        case .other:
            let name = exercise.name.lowercased()
            return !externalLoadOtherKeywords.contains(where: name.contains)
        default:
            return false
        }
    }

    /// `.other`-equipment movements whose resistance is an external implement, not the
    /// athlete's body — excluded from bodyweight credit so their stored weight is read as
    /// the whole load. "band hamstring"/"head harness" are worded to spare the genuinely
    /// bodyweight "band assisted pull-up".
    private static let externalLoadOtherKeywords: [String] = [
        "sled", "plate", "trap bar", "sledgehammer", "heavy bag", "battling",
        "wrist roller", "balance board", "head harness", "band hamstring",
    ]

    /// A hold measured in seconds rather than reps (plank, side bridge, the isometrics).
    /// Read from the catalog's own `static` force facet rather than a hand-kept list, so
    /// a re-tuned catalog can't silently drift out of sync.
    static func isTimedHold(_ exercise: Exercise) -> Bool {
        guard isBodyweightLoaded(exercise), exercise.force == .static else { return false }
        // The catalog's `static` facet means "no concentric direction", which is not quite
        // the same as "measured in seconds". Prone Manual Hamstring is a partner-resisted
        // exercise performed for reps; labelling it a hold would print SECONDS in the live
        // log and divide its tonnage by three.
        return !repBasedStaticExIds.contains(exercise.id)
    }

    private static let repBasedStaticExIds: Set<String> = ["Prone_Manual_Hamstring"]

    // MARK: - The factor

    /// The fraction of bodyweight this movement loads, or `nil` when the movement isn't
    /// bodyweight-loaded at all (barbell work, stretching, cardio, bands).
    ///
    /// Resolution order: per-exercise override → name-keyword family → primary-muscle
    /// fallback. Order within the keyword table matters and is deliberate: "bench dip"
    /// must be tested before "dip", "incline push-up" before "push-up".
    static func factor(for exercise: Exercise) -> Double? {
        guard isBodyweightLoaded(exercise) else { return nil }
        if let override = overrides[exercise.id] { return override }
        let name = exercise.name.lowercased()
        for family in families where family.keywords.contains(where: name.contains) {
            return family.factor
        }
        return fallback(for: exercise)
    }

    /// Per-exercise values that no keyword rule should be bent to accommodate.
    /// The five holds plus one suspension exercise whose name reads like a crunch.
    private static let overrides: [String: Double] = [
        "Plank": 0.60,                                   // ~60% of BW on the forearms/toes
        "Side_Bridge": 0.55,                             // one-sided support, slightly less
        "Isometric_Chest_Squeezes": 0.10,                // arm against arm; almost no mass moves
        "Isometric_Neck_Exercise_-_Front_And_Back": 0.08,
        "Isometric_Neck_Exercise_-_Sides": 0.08,         // head + neck ~8% (Dempster)
        "Prone_Manual_Hamstring": 0.35,                  // partner-modulated single-limb lever
        "Gorilla_Chin_Crunch": 0.95,                     // hanging from a bar: suspension governs
    ]

    private struct Family {
        let keywords: [String]
        let factor: Double
    }

    /// Ordered most-specific first. Each entry's rationale is in PROGRESS_DESIGN.md §3.
    private static let families: [Family] = [
        // Suspension — the whole body hangs, minus the gripping hands and forearms.
        .init(keywords: ["pull-up", "pullup", "chin-up", "muscle-up"], factor: 0.95),
        .init(keywords: ["bench dip"], factor: 0.60),        // before "dip": feet carry ~40%
        .init(keywords: ["dip"], factor: 0.95),

        // Push-ups, most specific variant first.
        .init(keywords: ["handstand"], factor: 0.90),
        .init(keywords: ["incline push"], factor: 0.45),     // hands elevated: less mass forward
        .init(keywords: ["decline push", "feet elevated"], factor: 0.70),
        .init(keywords: ["pike push"], factor: 0.75),
        .init(keywords: ["push-up", "pushup", "push up"], factor: 0.64),

        // Ballistics — the entire body leaves the floor.
        .init(keywords: ["jump", "bound", "skipping", "butt kick", "hop"], factor: 1.00),

        // Lower body.
        .init(keywords: ["pistol", "sissy"], factor: 0.80),
        .init(keywords: ["squat", "lunge", "step-up"], factor: 0.75),
        .init(keywords: ["calf raise"], factor: 0.95),
        .init(keywords: ["glute-ham", "glute ham", "natural glute"], factor: 0.60),
        .init(keywords: ["bridge", "butt lift", "hip raise", "hip thrust"], factor: 0.45),
        .init(keywords: ["hyperextension", "back extension", "superman"], factor: 0.50),

        // Row — feet stay on the floor, so only part of the body is lifted.
        .init(keywords: ["inverted row", "body row"], factor: 0.60),

        // Trunk. Leg-raise family before the crunch family, so "reverse crunch" — which
        // lifts the legs, not the shoulders — isn't mistaken for a shoulder-blade crunch.
        .init(keywords: ["leg raise", "leg pull-in", "reverse crunch", "leg tuck",
                         "flutter", "pike", "knee raise"], factor: 0.30),
        .init(keywords: ["sit-up", "sit up", "jackknife", "cocoon", "v-up"], factor: 0.40),
        .init(keywords: ["crunch", "heel touch", "elbow to knee"], factor: 0.20),
        .init(keywords: ["mountain climber", "russian twist", "dead bug", "air bike",
                         "spider", "wind sprint"], factor: 0.25),

        // One limb through a partial range.
        .init(keywords: ["kickback", "leg lift", "fire hydrant"], factor: 0.15),
        .init(keywords: ["neck"], factor: 0.08),
    ]

    /// Anything the keyword table doesn't name, placed by what it primarily trains.
    /// Approximate by construction — the catch-all deliberately sits low.
    private static func fallback(for exercise: Exercise) -> Double {
        // Unnamed plyometrics are sprint and agility drills (wall drills, carioca, arm
        // action) where a "rep" is a stride, not a lift. Crediting those at squat share
        // via their primary mover would badly overstate them.
        if exercise.category == .plyometrics { return 0.50 }
        guard let primary = exercise.primaryMuscles.first else { return 0.50 }
        switch primary {
        case .quadriceps, .glutes, .hamstrings, .adductors, .abductors, .calves:
            return 0.75
        case .chest, .triceps, .shoulders:
            return 0.64
        case .lats, .middleBack, .traps, .biceps, .forearms:
            return 0.95
        case .abdominals, .lowerBack:
            return 0.30
        case .neck:
            return 0.08
        }
    }

    // MARK: - Load

    /// The load a set actually represents, in kilograms.
    ///
    /// For bodyweight movements the stored weight is *added* load — a dip belt or a
    /// vest — layered on top of the bodyweight share. For everything else it is the
    /// load itself. A nil exercise (an id no longer in the catalog) falls back to the
    /// stored weight, which is always the safe reading.
    static func effectiveKg(addedKg: Double, exercise: Exercise?, bodyweightKg: Double?) -> Double {
        guard let exercise, let factor = factor(for: exercise),
              let bodyweightKg, bodyweightKg > 0 else { return addedKg }
        return factor * bodyweightKg + addedKg
    }

    /// Rep-equivalents for one logged set: a timed hold's `reps` field holds seconds, so
    /// 30 s of plank counts as 10 rep-equivalents rather than 30 reps.
    static func repEquivalents(reps: Int, exercise: Exercise?) -> Double {
        guard let exercise, isTimedHold(exercise) else { return Double(reps) }
        return Double(reps) / secondsPerRepEquivalent
    }
}
