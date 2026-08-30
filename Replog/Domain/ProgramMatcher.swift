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
    /// How long one session may run. Collected at onboarding and, until now, thrown away:
    /// the matcher could not tell a 20-minute hotel circuit from a 75-minute gym session.
    var minutesPerSession: Int
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
         minutesPerSession: Int = 45,
         equipment: Set<Equipment> = [],
         satisfiesPrerequisites: Bool = false) {
        self.goal = goal
        self.sport = sport
        self.customSport = customSport
        self.experience = experience
        self.gender = gender
        self.age = age
        self.daysPerWeek = daysPerWeek
        self.minutesPerSession = minutesPerSession
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
                     minutesPerSession: quiz.minutesPerSession,
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

    /// Maps a free-text sport onto a known program sport token, or nil.
    ///
    /// Matched on whole WORDS rather than substrings. Substring matching quietly said that
    /// "skipping" is skiing, "underwater basket weaving" is basketball and "mountain biking"
    /// is hiking (because "mountain" was a hiking key and was tested before the bike words).
    /// Each of those hands an athlete a training programme for a sport they do not play, so
    /// the variants are spelled out instead of inferred from a prefix. Anything unrecognised
    /// returns nil, and the athlete gets general athletic work — the right answer for a sport
    /// this library does not cover.
    private static func matchCustomSport(_ raw: String) -> String? {
        let words = Set(raw.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !words.isEmpty else { return nil }
        let known: [(keys: Set<String>, token: String)] = [
            (["climbing", "climb", "bouldering", "boulder"], "climbing"),
            (["golf", "golfing"], "golf"),
            (["hiking", "hike", "trekking", "trek", "hillwalking", "mountaineering"], "hiking"),
            (["skiing", "ski", "snowboarding", "snowboard"], "skiing"),
            (["tennis", "padel", "paddle", "squash", "racquetball", "badminton"], "tennis_padel"),
            (["triathlon", "ironman", "duathlon"], "triathlon"),
            (["running", "run", "runner", "jogging", "jog", "marathon", "5k", "10k"], "running"),
            (["swimming", "swim", "swimmer"], "swimming"),
            (["cycling", "cycle", "cyclist", "biking", "bike", "mtb", "spinning"], "cycling"),
            (["boxing", "box", "mma", "kickboxing", "muaythai", "sparring"], "boxing"),
            (["basketball", "hoops"], "basketball"),
            (["volleyball"], "volleyball"),
            (["football", "soccer", "futsal"], "football"),
        ]
        for entry in known where !entry.keys.isDisjoint(with: words) {
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
        // A program with no day templates cannot become a plan: the builder resolves zero
        // workouts and the whole thing silently falls through to the legacy split generator,
        // leaving the athlete with a plan that is not the program they were shown.
        guard !program.days.isEmpty else { return nil }
        guard equipmentSatisfied(program, by: context.equipment) else { return nil }
        guard program.audience.admits(age: context.age) else { return nil }
        guard sportGatePasses(program, for: context) else { return nil }

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

        // Days-per-week fit. The athlete named a number; a program two or more days away
        // from it is a different commitment, so the distance now carries a real penalty
        // rather than merely forfeiting a bonus.
        let dayGap = abs(program.daysPerWeek - context.daysPerWeek)
        score += dayFitScore(gap: dayGap)
        if dayGap == 0 {
            reasons.append("Fits your \(context.daysPerWeek) days/week.")
        } else if dayGap == 1 {
            reasons.append("Close to your \(context.daysPerWeek) days/week (\(program.daysPerWeek)).")
        }

        // Session-length fit. This is the term whose absence handed an athlete with 85
        // minutes a 20-minute hotel-room circuit: nothing in the scoring could tell the
        // difference, so goal words and an exact day count carried a maintenance program
        // past every real training program in the library.
        let fit = sessionFitScore(programMinutes: program.sessionMinutes,
                                  athleteMinutes: context.minutesPerSession)
        score += fit
        if let reason = sessionFitReason(programMinutes: program.sessionMinutes,
                                         athleteMinutes: context.minutesPerSession) {
            reasons.append(reason)
        }

        // Prerequisite: a caution, not a wall.
        //
        // It used to be a hard gate keyed on a single boolean that is ALWAYS false during
        // onboarding — which is the one moment the app generates a plan. Every endurance
        // sport in the library declares a prerequisite ("Can run 5K continuously"), so a
        // runner, cyclist, swimmer or triathlete could never be given their own sport's
        // programme at all; they got generic athletic work instead. The same boolean was
        // simultaneously too loose afterwards: any logged history at all flipped it true and
        // unlocked all twelve, whatever each one actually asks for.
        //
        // As a penalty it does the job the gate was meant to do — an equivalent programme
        // with no entry requirement is preferred — while still being reachable when it is
        // the only thing that serves the athlete. What it expects is on its detail screen.
        if program.prerequisite != nil && !context.satisfiesPrerequisites {
            score -= 25
            reasons.append("Assumes some training already behind you — check what it expects.")
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

    // MARK: Fit scoring

    /// How well a program's weekly frequency matches the athlete's answer.
    ///
    /// Exact is worth more than any single goal keyword, because "three days a week" is a
    /// promise about the athlete's life rather than a preference about training style.
    static func dayFitScore(gap: Int) -> Double {
        switch gap {
        case 0:  return 30
        case 1:  return 14
        case 2:  return 0
        default: return -22
        }
    }

    /// How well a program's session length matches the time the athlete set aside.
    ///
    /// Scored as a RATIO rather than a difference, so it behaves the same for someone with
    /// 20 minutes and someone with 90: half the time you have is half the time you have.
    /// A missing figure on either side scores neutral rather than guessing.
    ///
    /// The two directions are not symmetric, because the mistakes are not symmetric. A
    /// program that needs MORE time than the athlete has cannot be finished — it is close to
    /// disqualifying. A program that needs less merely leaves time on the table, so it is
    /// penalised on a smooth slope instead of a cliff: bucketing scored a 20-minute and a
    /// 40-minute program identically against a 90-minute athlete, which let the shorter one
    /// win on unrelated points. Continuity is what makes "closest available" actually mean
    /// closest, whatever the library happens to contain.
    static func sessionFitScore(programMinutes: Int, athleteMinutes: Int) -> Double {
        guard programMinutes > 0, athleteMinutes > 0 else { return 0 }
        let ratio = Double(programMinutes) / Double(athleteMinutes)
        if ratio > 1.35 { return -60 }                       // will not fit in the time they have
        if ratio >= 0.75 { 
            return ratio <= 1.15 ? 26                        // fits the slot
                                 : 26 - (ratio - 1.15) * 120 // slightly over, tapering
        }
        // Under-use, straight-line from "fine" at 0.75 down to "barely a session" at 0.
        return -45 + 49 * (ratio / 0.75)
    }

    /// The plain-language reason attached to a session-length verdict, or nil when the fit
    /// is unremarkable enough not to be worth a line in the report.
    static func sessionFitReason(programMinutes: Int, athleteMinutes: Int) -> String? {
        guard programMinutes > 0, athleteMinutes > 0 else { return nil }
        let ratio = Double(programMinutes) / Double(athleteMinutes)
        if ratio >= 0.75 && ratio < 1.16 {
            return "Built for the ~\(athleteMinutes) minutes you have."
        }
        return nil
    }

    /// Whether a program is a defensible answer for this athlete at all — as opposed to
    /// merely the least bad thing the library happens to hold.
    ///
    /// Ranking always produces a winner, even when every candidate is wrong: with 90 minutes
    /// and nothing but bodyweight, the library's best offer is a 40-minute program, and
    /// "best available" quietly became "half the session you asked for". When nothing fits,
    /// the caller is better off building a plan from the catalog to the athlete's own time
    /// and days than dressing a mismatch up as a recommendation. As the library grows this
    /// answers true more often; it needs no maintenance to stay correct.
    static func fitsTheAthlete(_ program: WorkoutProgram, for context: MatchContext) -> Bool {
        guard program.sessionMinutes > 0, context.minutesPerSession > 0 else { return true }
        let ratio = Double(program.sessionMinutes) / Double(context.minutesPerSession)
        return ratio >= 0.5 && ratio <= 1.35
    }

    // MARK: Sport gate

    /// A program written for one sport is for that sport's athletes, and nobody else.
    ///
    /// The gate used to open with `guard context.goal == .sport else { return true }`, which
    /// let all 17 sport-specific programs through for every OTHER goal. Nothing downstream
    /// says a basketball block is not a hypertrophy plan — its goals (`power`, `vertical_jump`,
    /// `speed`) simply score zero overlap — so it could win on day count and session length
    /// alone and be handed to someone who never mentioned basketball. That is exactly what
    /// happened. The sport question is asked first now, whatever the goal:
    ///
    ///  • sport-agnostic and general/GPP programs: eligible for everyone;
    ///  • a specific sport's program: only for an athlete training for THAT sport.
    ///
    /// This gates recommendation, not access — the Programs tab still lists all 62, and an
    /// athlete who wants the basketball block can pick it themselves.
    private static func sportGatePasses(_ program: WorkoutProgram, for context: MatchContext) -> Bool {
        guard let programSport = program.sport?.lowercased(),
              programSport != "general" else { return true }   // agnostic / GPP: always eligible
        // A sport-specific program is only ever right for someone training for that sport.
        guard context.goal == .sport, let token = context.sportToken else { return false }
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
            // "maintenance" is deliberately absent: holding what you have is the opposite of
            // recomposition, and counting it here is what let a hotel-room maintenance
            // circuit score as a match for someone trying to change their body.
            return ["muscle_building", "muscle_retention", "weight_loss",
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

    /// A ranking nudge when a program's sex focus aligns with the athlete — and a push in
    /// the other direction when it is aimed squarely at someone else.
    ///
    /// Never a gate: a program stays reachable whoever the athlete is, and the Programs tab
    /// still lists every one of them. But an alignment bonus alone is not symmetric — it
    /// left "Women's Upper Strength" as the top recommendation for a male athlete, which
    /// reads as the app not having looked at the answers it just collected. The penalty is
    /// smaller than a day-count mismatch, so a genuinely better-fitting program still wins.
    private static func sexFocusBonus(_ program: WorkoutProgram, gender: Gender) -> (points: Double, reason: String)? {
        switch (program.audience.sex, gender) {
        case (.female, .female), (.femaleFocused, .female):
            return (15, "Designed with women in mind.")
        case (.maleFocused, .male):
            return (8, "Emphasis suited to your profile.")
        case (.female, .male), (.femaleFocused, .male), (.maleFocused, .female):
            return (-20, "Written for a different athlete, but still open to you.")
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
        //
        // `medicine_ball` sits here rather than in the strict bucket below because the
        // onboarding chip grid renders `Equipment.selectable`, which does not offer it —
        // so `allowedEquipment` could never contain it for ANY athlete, and the three
        // programmes requiring one (boxing, tennis/padel, golf) were gated out for 100% of
        // users, including the athletes they were written for. A boxer got generic GPP
        // instead. Gating on gear the quiz never asks about can only ever return false.
        case "body_only", "bodyweight", "pull_up_bar", "backpack", "backpack_for_load",
             "open_space", "sandbag", "medicine_ball":
            return true
        // App-modeled strength gear — strict gate.
        case "barbell", "trap_bar":       return owned.contains(.barbell)
        case "dumbbell":                  return owned.contains(.dumbbell)
        case "machine":                   return owned.contains(.machine)
        case "cable":                     return owned.contains(.cable)
        case "kettlebell", "kettlebells": return owned.contains(.kettlebells)
        case "bands":                     return owned.contains(.bands)
        // Cardio gear the app doesn't model — stay permissive (can't disprove ownership).
        case "bike", "trainer", "rower", "elliptical", "pool", "treadmill":
            return true
        // Unknown token — don't exclude on something we can't reason about.
        default:
            return true
        }
    }
}
