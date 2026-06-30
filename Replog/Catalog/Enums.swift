//
//  Enums.swift
//  Replog
//
//  Shared enumerations for the static exercise catalog and user data.
//  All string enums decode leniently so every entry in the Free Exercise DB
//  parses even if a future value is added upstream.
//

import Foundation

/// A muscle group targeted by an exercise (Free Exercise DB taxonomy).
enum Muscle: String, Codable, CaseIterable, Identifiable, Sendable {
    case abdominals, abductors, adductors, biceps, calves, chest, forearms
    case glutes, hamstrings, lats, lowerBack = "lower back", middleBack = "middle back"
    case neck, quadriceps, shoulders, traps, triceps

    var id: String { rawValue }

    /// Human-facing, capitalized label ("lower back" -> "Lower Back").
    var displayName: String {
        rawValue.split(separator: " ").map(\.capitalized).joined(separator: " ")
    }
}

/// Equipment required for an exercise. `nil`/"None" upstream -> `.unknown` is avoided;
/// we model "no equipment recorded" as an optional on the model instead.
enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, machine, cable
    case bodyOnly = "body only"
    case bands, kettlebells
    case ezCurlBar = "e-z curl bar"
    case exerciseBall = "exercise ball"
    case foamRoll = "foam roll"
    case medicineBall = "medicine ball"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyOnly: return "Bodyweight"
        case .ezCurlBar: return "EZ Curl Bar"
        case .exerciseBall: return "Exercise Ball"
        case .foamRoll: return "Foam Roll"
        case .medicineBall: return "Medicine Ball"
        default: return rawValue.capitalized
        }
    }
}

/// Difficulty level. Drives the colored level badge in the Library.
enum Level: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, expert
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Whether the movement primarily pushes, pulls, or holds static.
enum Force: String, Codable, CaseIterable, Identifiable, Sendable {
    case push, pull, `static`
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Compound vs isolation movement.
enum Mechanic: String, Codable, CaseIterable, Identifiable, Sendable {
    case compound, isolation
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Broad training category.
enum ExerciseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength
    case stretching
    case plyometrics
    case cardio
    case powerlifting
    case olympicWeightlifting = "olympic weightlifting"
    case strongman

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .olympicWeightlifting: return "Olympic Weightlifting"
        default: return rawValue.capitalized
        }
    }
}

/// Day of the week a workout is scheduled on. Order follows the Today week strip (Sun-first).
enum Weekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case sun, mon, tue, wed, thu, fri, sat

    var id: String { rawValue }

    /// Short chip label, e.g. "Mon".
    var short: String { rawValue.capitalized }

    /// Uppercase tag used on the Today hero ("MON").
    var tag: String { rawValue.uppercased() }

    /// Calendar weekday number (1 = Sunday … 7 = Saturday), matching `Calendar`.
    var calendarWeekday: Int { (Weekday.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// The `Weekday` for a given `Date` in the current calendar.
    static func from(_ date: Date, calendar: Calendar = .current) -> Weekday {
        let comp = calendar.component(.weekday, from: date) // 1...7, Sunday = 1
        return allCases[(comp - 1) % 7]
    }
}
