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
    var name: String = "Alex"
    var goalRaw: String = Goal.buildMuscle.rawValue
    var streak: Int = 0
    var doneDates: [Date] = []
    var onboardingDone: Bool = false
    var totalWorkouts: Int = 0

    init(name: String = "Alex", goal: Goal = .buildMuscle) {
        self.name = name
        self.goalRaw = goal.rawValue
    }

    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .buildMuscle }
        set { goalRaw = newValue.rawValue }
    }

    /// The user's initial for the avatar.
    var initial: String { String(name.prefix(1)).uppercased() }
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
