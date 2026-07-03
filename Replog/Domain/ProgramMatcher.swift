//
//  ProgramMatcher.swift
//  Replog
//
//  Deterministic, pure selection of candidate programs from the bundled library for a given
//  athlete. This is the first stage of program-driven planning: it narrows 62 programs down
//  to a ranked shortlist that the AI framing call (Phase 3) — or the deterministic fallback —
//  then chooses from.
//
//  Two layers:
//   • Hard gates remove programs the athlete can't or shouldn't run: equipment they lack,
//     an age outside the audience band, a sport mismatch when training for a sport, an
//     unmet prerequisite, and (for auto-pick) any program carrying a medical disclaimer.
//   • Soft scoring ranks the survivors by goal overlap, days-per-week fit, experience fit,
//     and a (never-exclusionary) sex-focus nudge.
//
//  All inputs are plain values (`MatchContext`) so every rule is unit-testable without a
//  store or the catalog singleton.
//

import Foundation

// MARK: - Input

/// The athlete facts the matcher reasons about. Built from `QuizAnswers` at onboarding, but
/// deliberately a standalone value type so tests can construct any persona directly.
struct MatchContext: Equatable, Sendable {
    var goal: Goal
    var sport: Sport?
    var customSport: String
    var experience: Experience
    var gender: Gender
    var age: Int
    var daysPerWeek: Int
    /// The equipment the athlete can train with (already resolved from access level / picks).
    var equipment: Set<Equipment>
    /// Whether the athlete's history satisfies gated prerequisites. False at onboarding
    /// (a brand-new user has no history), so prerequisite programs are gated out by default.
    var satisfiesPrerequisites: Bool

    init(goal: Goal = .buildMuscle,
         sport: Sport? = nil,
         customSport: String = "",
         experience: Experience = .beginner,
         gender: Gender = .male,
         age: Int = 28,
         daysPerWeek: Int = 3,
         equipment: Set<Equipment> = [],
         satisfiesPrerequisites: Bool = false) {
        self.goal = goal
        self.sport = sport
        self.customSport = customSport
        self.experience = experience
        self.gender = gender
        self.age = age
        self.daysPerWeek = daysPerWeek
        self.equipment = equipment
        self.satisfiesPrerequisites = satisfiesPrerequisites
    }

    /// Builds a context from onboarding answers. `satisfiesPrerequisites` defaults to false
    /// because onboarding users have no logged history to prove a prerequisite.
    static func from(_ quiz: QuizAnswers, satisfiesPrerequisites: Bool = false) -> MatchContext {
        MatchContext(goal: quiz.goal,
                     sport: quiz.sport,
                     customSport: quiz.customSport,
                     experience: quiz.experience,
                     gender: quiz.gender,
                     age: quiz.age,
                     daysPerWeek: quiz.daysPerWeek,
                     equipment: quiz.allowedEquipment,
                     satisfiesPrerequisites: satisfiesPrerequisites)
    }

    /// The program-library sport token this athlete is training for, when goal is Sport.
    /// A named sport maps directly; an "Other" free-text sport maps by keyword, and an
    /// unrecognised custom sport returns nil — the matcher then favours the general-athlete
    /// (GPP) program as the fallback.
    var sportToken: String? {
        guard goal == .sport, let sport else { return nil }
        switch sport {
        case .running:    return "running"
        case .swimming:   return "swimming"
        case .football:   return "football"
        case .basketball: return "basketball"
        case .cycling:    return "cycling"
        case .boxing:     return "boxing"
        case .volleyball: return "volleyball"
        case .other:      return Self.matchCustomSport(customSport)
        }
    }

    /// Maps a free-text sport onto a known program sport token by keyword, or nil.
    private static func matchCustomSport(_ raw: String) -> String? {
        let s = raw.lowercased()
        let known: [(keys: [String], token: String)] = [
            (["climb", "boulder"], "climbing"),
            (["golf"], "golf"),
            (["hike", "hiking", "mountain", "trek"], "hiking"),
            (["ski", "snowboard"], "skiing"),
            (["tennis", "padel", "racquet", "racket", "squash"], "tennis_padel"),
            (["triathlon", "ironman"], "triathlon"),
            (["run", "marathon", "5k", "10k"], "running"),
            (["swim"], "swimming"),
            (["cycl", "bike"], "cycling"),
            (["box", "mma", "kickbox"], "boxing"),
            (["basket"], "basketball"),
            (["volley"], "volleyball"),
            (["soccer", "football"], "football"),
        ]
        for entry in known where entry.keys.contains(where: { s.contains($0) }) {
            return entry.token
        }
        return nil
    }
}

// MARK: - Output

/// A ranked candidate program with its score, the reasons behind it, and whether it may be
/// selected automatically (programs with a medical disclaimer never can).
nonisolated struct ProgramMatch: Equatable, Sendable {
    let program: WorkoutProgram
    let score: Double
    let autoPickable: Bool
    let reasons: [String]

    var id: String { program.id }
}

// MARK: - Matcher

enum ProgramMatcher {

    /// Ranks every program in the catalog for the athlete, best first. Programs failing a
    /// hard gate are dropped. Ties break by descending score, then program id for stability.
    static func rank(_ context: MatchContext, in catalog: ProgramCatalog) -> [ProgramMatch] {
        rank(context, programs: catalog.all)
    }

    /// Testable core over an explicit program list.
    static func rank(_ context: MatchContext, programs: [WorkoutProgram]) -> [ProgramMatch] {
        programs
            .compactMap { score($0, for: context) }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.program.id < rhs.program.id
            }
    }

    /// The top N candidates (default 5) for the framing prompt / fallback.
    static func candidates(_ context: MatchContext, in catalog: ProgramCatalog, limit: Int = 5) -> [ProgramMatch] {
        Array(rank(context, in: catalog).prefix(limit))
    }

    /// The single program the deterministic path would pick: the highest-scoring candidate
    /// that may be auto-selected (i.e. carries no medical disclaimer). Nil if none qualify.
    static func topAutoPick(_ context: MatchContext, in catalog: ProgramCatalog) -> WorkoutProgram? {
        rank(context, in: catalog).first { $0.autoPickable }?.program
    }

    // MARK: Gating + scoring

    /// Applies hard gates then computes a soft score. Returns nil when a hard gate excludes
    /// the program.
    static func score(_ program: WorkoutProgram, for context: MatchContext) -> ProgramMatch? {
        // ---- Hard gates ----
        guard equipmentSatisfied(program, by: context.equipment) else { return nil }
        guard program.audience.admits(age: context.age) else { return nil }
        guard sportGatePasses(program, for: context) else { return nil }
        if program.prerequisite != nil && !context.satisfiesPrerequisites { return nil }

        // ---- Soft scoring ----
        var score = 0.0
        var reasons: [String] = []

        // Sport match (only relevant when training for a sport). A direct sport program is
        // the strongest possible signal; the GPP fallback wins when no sport program exists.
        if context.goal == .sport {
            if let token = context.sportToken,
               program.sport?.caseInsensitiveCompare(token) == .orderedSame {
                score += 100
                reasons.append("Built specifically for \(program.sport ?? token).")
            } else if isGeneralAthletic(program) {
                score += 40
                reasons.append("General athletic base — supports any sport.")
            }
        }

        // Goal overlap against the program's goals + category.
        let goalHits = goalOverlap(program, goal: context.goal)
        if goalHits > 0 {
            score += Double(goalHits) * 12
            reasons.append("Matches your \(context.goal.shortName.lowercased()) goal.")
        }

        // Days-per-week fit: full marks on an exact match, tapering with distance.
        let dayGap = abs(program.daysPerWeek - context.daysPerWeek)
        let dayScore = max(0, 20 - dayGap * 7)
        score += Double(dayScore)
        if dayGap == 0 {
            reasons.append("Fits your \(context.daysPerWeek) days/week.")
        } else if dayGap == 1 {
            reasons.append("Close to your \(context.daysPerWeek) days/week (\(program.daysPerWeek)).")
        }

        // Experience fit.
        if experienceFits(program, level: context.experience) {
            score += 18
            reasons.append("Pitched at \(context.experience.displayName.lowercased()) level.")
        }

        // Sex focus — a nudge, never a gate.
        if let bonus = sexFocusBonus(program, gender: context.gender) {
            score += bonus.points
            reasons.append(bonus.reason)
        }

        return ProgramMatch(program: program,
                            score: score,
                            autoPickable: !program.requiresDisclaimerAcknowledgement,
                            reasons: reasons)
    }

    // MARK: Sport gate

    /// When training for a sport, exclude programs built for a *different* specific sport
    /// (a runner shouldn't be handed the golf program); general and sport-agnostic programs
    /// stay eligible as fallbacks. Non-sport goals don't apply this gate.
    private static func sportGatePasses(_ program: WorkoutProgram, for context: MatchContext) -> Bool {
        guard context.goal == .sport else { return true }
        guard let programSport = program.sport?.lowercased(),
              programSport != "general" else { return true }   // agnostic / GPP: always eligible
        // A sport-specific program is eligible only if it's the athlete's sport.
        guard let token = context.sportToken else {
            // Unrecognised custom sport → keep only general/agnostic programs.
            return false
        }
        return programSport == token.lowercased()
    }

    /// Whether a program is a general-athletic base (its sport is "general", or it's tagged
    /// for broad athleticism) — the sensible fallback for an unmatched sport athlete.
    private static func isGeneralAthletic(_ program: WorkoutProgram) -> Bool {
        if program.sport?.caseInsensitiveCompare("general") == .orderedSame { return true }
        let athleticGoals: Set<String> = ["general_athleticism", "athletic_base", "multi_sport", "power"]
        return !Set(program.goals).isDisjoint(with: athleticGoals)
    }

    // MARK: Goal overlap

    /// How many of the program's goals/category tokens align with the athlete's goal.
    private static func goalOverlap(_ program: WorkoutProgram, goal: Goal) -> Int {
        let wanted = goalTokens(for: goal)
        var tokens = Set(program.goals)
        tokens.insert(program.category)
        return tokens.intersection(wanted).count
    }

    /// The library goal/category tokens each app goal favours.
    private static func goalTokens(for goal: Goal) -> Set<String> {
        switch goal {
        case .buildMuscle:
            return ["muscle_building", "hypertrophy", "aesthetics", "strength_hypertrophy",
                    "upper_body_development", "arm_development", "glute_development",
                    "leg_strength", "strength"]
        case .loseWeight:
            return ["weight_loss", "fat_loss", "conditioning", "work_capacity",
                    "energy", "endurance"]
        case .recomp:
            return ["muscle_building", "muscle_retention", "maintenance", "weight_loss",
                    "recomp", "strength_hypertrophy", "general_fitness"]
        case .sport:
            return ["general_athleticism", "athletic_base", "power", "speed", "conditioning",
                    "sport_support", "multi_sport", "sport_conditioning"]
        }
    }

    // MARK: Experience fit

    /// Whether the program's (free-text) experience level admits the athlete's level. "any"
    /// admits everyone; otherwise we look for the level keyword as a substring so compound
    /// values like "beginner_intermediate" or "intermediate_advanced" match sensibly.
    private static func experienceFits(_ program: WorkoutProgram, level: Experience) -> Bool {
        let raw = program.audience.experienceLevel.lowercased()
        if raw.contains("any") { return true }
        switch level {
        case .beginner:
            return raw.contains("beginner") || raw.contains("novice") || raw.contains("absolute")
        case .intermediate:
            return raw.contains("intermediate") || raw.contains("novice")
        case .advanced:
            return raw.contains("advanced") || raw.contains("intermediate_advanced")
        }
    }

    // MARK: Sex focus

    /// A small, never-exclusionary ranking nudge when a program's sex focus aligns with the
    /// athlete. `female` and `female_focused` programs stay available to everyone.
    private static func sexFocusBonus(_ program: WorkoutProgram, gender: Gender) -> (points: Double, reason: String)? {
        switch (program.audience.sex, gender) {
        case (.female, .female), (.femaleFocused, .female):
            return (15, "Designed with women in mind.")
        case (.maleFocused, .male):
            return (8, "Emphasis suited to your profile.")
        default:
            return nil
        }
    }

    // MARK: Equipment gate

    /// Whether the athlete's equipment satisfies every *required* item. Follows the app's
    /// "missing equipment counts as bodyweight" convention: bodyweight and calisthenics-staple
    /// tokens are always satisfied; app-modeled strength gear gates strictly; cardio gear the
    /// app doesn't model stays permissive so a cyclist/swimmer isn't wrongly excluded.
    static func equipmentSatisfied(_ program: WorkoutProgram, by owned: Set<Equipment>) -> Bool {
        program.equipmentRequired.allSatisfy { tokenSatisfied($0, by: owned) }
    }

    /// A single required token; compound "a_or_b" tokens pass if any branch passes.
    private static func tokenSatisfied(_ token: String, by owned: Set<Equipment>) -> Bool {
        let key = token.lowercased().trimmingCharacters(in: .whitespaces)
        if key.contains("_or_") {
            return key.components(separatedBy: "_or_").contains { tokenSatisfied($0, by: owned) }
        }
        switch key {
        // Always available: bodyweight & near-universal staples.
        case "body_only", "bodyweight", "pull_up_bar", "backpack", "backpack_for_load",
             "open_space", "sandbag":
            return true
        // App-modeled strength gear — strict gate.
        case "barbell", "trap_bar":       return owned.contains(.barbell)
        case "dumbbell":                  return owned.contains(.dumbbell)
        case "machine":                   return owned.contains(.machine)
        case "cable":                     return owned.contains(.cable)
        case "kettlebell", "kettlebells": return owned.contains(.kettlebells)
        case "bands":                     return owned.contains(.bands)
        case "medicine_ball":             return owned.contains(.medicineBall)
        // Cardio gear the app doesn't model — stay permissive (can't disprove ownership).
        case "bike", "trainer", "rower", "elliptical", "pool", "treadmill":
            return true
        // Unknown token — don't exclude on something we can't reason about.
        default:
            return true
        }
    }
}
