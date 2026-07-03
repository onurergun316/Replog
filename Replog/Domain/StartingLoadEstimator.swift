//
//  StartingLoadEstimator.swift
//  Replog
//
//  Computes a science-based STARTING working load (kg) per user, per exercise — never a
//  hardcoded number. Program templates specify only sets/reps/RPE; the absolute load is
//  derived here from the individual (sex, experience, bodyweight) and the movement, and is
//  deliberately CONSERVATIVE (err low) because `LoadCalibrator` + the progression engine
//  correct it upward from real logged sets within a session or two.
//
//  Model (all coefficients are named constants with their sources):
//   1. Base = a bodyweight-relative 1RM anchor for an UNTRAINED reference male, per movement
//      pattern (lower compound > upper push > upper pull > isolation). Conservative, widely
//      published beginner ratios (exrx.net / StrengthLevel "untrained" bands, rounded down).
//   2. Rep/RPE → working load via the existing Epley relationship (`Formulas.e1rm`): the load
//      that leaves the target reps-in-reserve at the target reps.
//   3. Sex scaling of the STARTING estimate only (never progression rate): women average
//      ~50–60% of male upper-body strength and ~60–70% of lower-body (the gap is ~2× larger
//      for upper body — Bishop et al. 1987; Miller et al. 1993). Encoded as two coefficients.
//   4. Experience scaling (untrained → trained can start heavier). Response to training is
//      equal by sex, so sex scaling is applied to the estimate only.
//   5. Rounding to the real equipment increment, with an empty-bar floor for barbells and a
//      no-external-load result for bodyweight movements.
//

import Foundation

/// The way an exercise is loaded — drives increment rounding and per-hand splitting.
nonisolated enum LoadingType: Equatable, Sendable {
    case barbell
    case dumbbellPerHand
    case machine
    case cable
    case bodyweight
    case other        // med ball, small implements — light, 1 kg increments
}

/// Which broad strength pattern the movement is, for the bodyweight-ratio anchor.
nonisolated enum StrengthPattern: Equatable, Sendable {
    case lowerCompound   // squat, hinge, lunge, leg press
    case upperPush       // bench, overhead press, dips
    case upperPull       // row, pulldown, pull-up
    case isolation       // curls, raises, extensions, calves
}

/// The athlete facts the estimate needs.
nonisolated struct LoadUser: Equatable, Sendable {
    var sex: Gender
    var experience: Experience
    var bodyweightKg: Double
    var age: Int?

    init(sex: Gender = .male, experience: Experience = .beginner,
         bodyweightKg: Double = 75, age: Int? = nil) {
        self.sex = sex
        self.experience = experience
        self.bodyweightKg = bodyweightKg
        self.age = age
    }

    /// Built from onboarding answers.
    static func from(_ answers: QuizAnswers) -> LoadUser {
        LoadUser(sex: answers.gender, experience: answers.experience,
                 bodyweightKg: answers.bodyWeightKg, age: answers.age)
    }
}

/// A movement's loading request, decoupled from `Exercise` so the core is unit-testable.
nonisolated struct LoadRequest: Equatable, Sendable {
    var pattern: StrengthPattern
    var loading: LoadingType
    var targetReps: Int
    var targetRPE: Int
}

/// The estimated starting load.
nonisolated struct LoadEstimate: Equatable, Sendable {
    /// Working weight in kg (per hand for dumbbells). 0 for bodyweight movements.
    var kg: Double
    /// True when the movement carries no external load (bodyweight/assisted).
    var isBodyweight: Bool
    /// One-line explanation of the source, for the coach's reason string.
    var note: String
}

enum StartingLoadEstimator {

    // MARK: - Named constants (with sources)

    /// Untrained reference-male 1RM as a fraction of bodyweight, per pattern. Conservative
    /// (rounded down from published untrained standards) — the calibrator corrects upward.
    static let baseRatioLowerCompound = 0.70   // e.g. untrained back squat ≈ 0.7× BW
    static let baseRatioUpperPush     = 0.45   // bench press
    static let baseRatioUpperPull     = 0.42   // barbell row / pulldown
    static let baseRatioIsolation     = 0.15   // curl / raise (total external load)

    /// Female : male starting-strength ratio. Upper ~0.55, lower ~0.68 — the upper/lower gap
    /// difference is the key finding (Bishop 1987; Miller 1993). Applied to the ESTIMATE only.
    static let femaleUpperCoeff = 0.55
    static let femaleLowerCoeff = 0.68
    /// Unspecified sex: a deliberate conservative midpoint between the female coeff and 1.0.
    static var unspecifiedUpperCoeff: Double { (femaleUpperCoeff + 1.0) / 2 }   // 0.775
    static var unspecifiedLowerCoeff: Double { (femaleLowerCoeff + 1.0) / 2 }   // 0.84

    /// Experience multipliers on the starting estimate (untrained reference = beginner = 1.0).
    static let beginnerMult     = 1.0
    static let intermediateMult = 1.4
    static let advancedMult     = 1.8

    /// The empty barbell floor — a barbell load never drops below this.
    static let emptyBarKg = 20.0

    // MARK: - Public API

    /// Estimates the starting working load for an abstract request.
    static func estimate(_ req: LoadRequest, user: LoadUser) -> LoadEstimate {
        if req.loading == .bodyweight {
            return LoadEstimate(kg: 0, isBodyweight: true,
                                note: "bodyweight to start — progress by reps or a harder variation")
        }
        let raw = unroundedKg(req, user: user)
        let kg = rounded(raw, loading: req.loading)
        return LoadEstimate(kg: kg, isBodyweight: false, note: note(for: user, req: req))
    }

    /// Estimates from a real catalog exercise for the given rep/RPE target and user.
    static func estimate(for exercise: Exercise, targetReps: Int, targetRPE: Int,
                         user: LoadUser) -> LoadEstimate {
        estimate(LoadRequest(pattern: pattern(for: exercise),
                             loading: loading(for: exercise),
                             targetReps: targetReps, targetRPE: targetRPE),
                 user: user)
    }

    // MARK: - Core computation

    /// The pre-rounding, pre-floor working load in kg (per hand for dumbbells). Exposed for
    /// tests that need the continuous value (e.g. the sex-gap ratio, before rounding noise).
    static func unroundedKg(_ req: LoadRequest, user: LoadUser) -> Double {
        let base1RM = baseRatio(req.pattern) * user.bodyweightKg          // reference-male 1RM
        // Epley inverse: the load leaving (10 − RPE) reps in reserve at the target reps.
        let repsToFailure = Double(max(1, req.targetReps) + max(0, 10 - req.targetRPE))
        let refWorking = base1RM / (1 + repsToFailure / 30)
        var kg = refWorking * sexCoeff(req.pattern, sex: user.sex)
            * experienceMult(user.experience) * ageFactor(user.age)
        if req.loading == .dumbbellPerHand { kg /= 2 }                    // load per hand
        return max(0, kg)
    }

    private static func baseRatio(_ p: StrengthPattern) -> Double {
        switch p {
        case .lowerCompound: return baseRatioLowerCompound
        case .upperPush:     return baseRatioUpperPush
        case .upperPull:     return baseRatioUpperPull
        case .isolation:     return baseRatioIsolation
        }
    }

    private static func isUpper(_ p: StrengthPattern) -> Bool {
        p == .upperPush || p == .upperPull || p == .isolation
    }

    static func sexCoeff(_ pattern: StrengthPattern, sex: Gender) -> Double {
        let upper = isUpper(pattern)
        switch sex {
        case .male:           return 1.0
        case .female:         return upper ? femaleUpperCoeff : femaleLowerCoeff
        case .preferNotToSay: return upper ? unspecifiedUpperCoeff : unspecifiedLowerCoeff
        }
    }

    private static func experienceMult(_ e: Experience) -> Double {
        switch e {
        case .beginner:     return beginnerMult
        case .intermediate: return intermediateMult
        case .advanced:     return advancedMult
        }
    }

    /// A gentle taper for older athletes (sarcopenia); conservative and optional.
    private static func ageFactor(_ age: Int?) -> Double {
        guard let age else { return 1.0 }
        if age >= 70 { return 0.80 }
        if age >= 60 { return 0.90 }
        return 1.0
    }

    // MARK: - Rounding to real increments

    private static func rounded(_ kg: Double, loading: LoadingType) -> Double {
        switch loading {
        case .barbell:
            // Never below an empty bar; otherwise snap to 2.5 kg.
            let snapped = (kg / 2.5).rounded() * 2.5
            return max(emptyBarKg, snapped)
        case .dumbbellPerHand:
            // Light dumbbells come in ~1 kg steps; heavier in 2.5 kg. Floor at 1 kg.
            let step = kg < 10 ? 1.0 : 2.5
            return max(1.0, (kg / step).rounded() * step)
        case .machine:
            // Plausible pin-stack step; floor at one plate.
            return max(5.0, (kg / 5.0).rounded() * 5.0)
        case .cable:
            return max(2.5, (kg / 2.5).rounded() * 2.5)
        case .other:
            return max(1.0, kg.rounded())
        case .bodyweight:
            return 0
        }
    }

    // MARK: - Exercise mapping

    static func loading(for exercise: Exercise) -> LoadingType {
        switch exercise.equipment {
        case .barbell, .ezCurlBar:      return .barbell
        case .dumbbell, .kettlebells:   return .dumbbellPerHand
        case .machine:                  return .machine
        case .cable:                    return .cable
        case .medicineBall:             return .other
        case .bodyOnly, .bands, .foamRoll, .exerciseBall, .none:
            return .bodyweight
        case .other:                    return .other
        }
    }

    static func pattern(for exercise: Exercise) -> StrengthPattern {
        let lowerMuscles: Set<Muscle> = [.quadriceps, .hamstrings, .glutes, .calves, .abductors, .adductors]
        let isLower = exercise.primaryMuscles.contains { lowerMuscles.contains($0) }
        let isCompound = exercise.mechanic == .compound

        if isLower { return isCompound ? .lowerCompound : .isolation }
        guard isCompound else { return .isolation }

        // Upper compound: push vs pull, from force, else from the primary muscle.
        if exercise.force == .push { return .upperPush }
        if exercise.force == .pull { return .upperPull }
        let pushMuscles: Set<Muscle> = [.chest, .shoulders, .triceps]
        return exercise.primaryMuscles.contains { pushMuscles.contains($0) } ? .upperPush : .upperPull
    }

    // MARK: - Reason copy

    private static func note(for user: LoadUser, req: LoadRequest) -> String {
        let sexWord: String
        switch user.sex {
        case .male: sexWord = "male"
        case .female: sexWord = "female"
        case .preferNotToSay: sexWord = ""
        }
        let level = user.experience.displayName.lowercased()
        let who = sexWord.isEmpty ? level : "\(sexWord) \(level)"
        return "starting estimate for a \(who); will calibrate to your logged sets"
    }
}
