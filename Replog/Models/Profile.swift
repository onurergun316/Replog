//
//  Profile.swift
//  Replog
//
//  Single-row user profile & app settings. Stored in SwiftData and fetched-or-created
//  via the helpers in ModelContainer+Replog.
//

import Foundation
import SwiftData

/// The user's training goal from onboarding.
enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case buildMuscle, loseWeight, recomp, sport
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .buildMuscle: return "Build muscle"
        case .loseWeight:  return "Lose weight"
        case .recomp:      return "Build muscle & lose fat"
        case .sport:       return "Train for a sport"
        }
    }
    /// Short label for chips / the Profile header.
    var shortName: String {
        switch self {
        case .buildMuscle: return "Hypertrophy"
        case .loseWeight:  return "Fat loss"
        case .recomp:      return "Recomposition"
        case .sport:       return "Sport"
        }
    }
}

/// Display unit for weights. Storage is always kg.
enum Units: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg, lb
    var id: String { rawValue }
    var label: String { rawValue }
}

@Model
final class UserProfile {
    /// The user's full name ("First Last"), captured during onboarding.
    var name: String = ""
    var goalRaw: String = Goal.buildMuscle.rawValue
    /// Consecutive scheduled workouts completed (see `StreakEngine.workoutStreak`).
    var streak: Int = 0
    /// Consecutive "perfect weeks" (see `StreakEngine.weekStreak`).
    var weekStreak: Int = 0
    var doneDates: [Date] = []
    var onboardingDone: Bool = false
    var totalWorkouts: Int = 0

    init(name: String = "", goal: Goal = .buildMuscle) {
        self.name = name
        self.goalRaw = goal.rawValue
    }

    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .buildMuscle }
        set { goalRaw = newValue.rawValue }
    }

    /// The consecutive-workout streak (alias for `streak`, for readable call sites).
    var workoutStreak: Int {
        get { streak }
        set { streak = newValue }
    }

    /// First name for greetings, falling back to a friendly default.
    var firstName: String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.isEmpty ? "there" : first
    }

    /// The user's initial for the avatar.
    var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}

@Model
final class AppSettings {
    var unitsRaw: String = Units.kg.rawValue
    var darkMode: Bool = false
    var restTimerAuto: Bool = false
    var restSeconds: Int = 90

    init() {}

    var units: Units {
        get { Units(rawValue: unitsRaw) ?? .kg }
        set { unitsRaw = newValue.rawValue }
    }
}
