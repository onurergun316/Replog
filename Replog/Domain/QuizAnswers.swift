//
//  QuizAnswers.swift
//  Replog
//
//  The onboarding intake. Feeds the deterministic PlanGenerator.
//

import Foundation

enum Experience: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female, preferNotToSay
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case running, swimming, football, basketball, cycling, boxing, volleyball, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .other: return "Other"
        default: return rawValue.capitalized
        }
    }

    /// Muscles a sport most depends on, highest priority first. `.other` has no fixed
    /// mapping — the plan falls back to general priorities.
    var priorityMuscles: [Muscle] {
        switch self {
        case .running:    return [.quadriceps, .hamstrings, .calves, .glutes, .abdominals]
        case .swimming:   return [.lats, .shoulders, .chest, .triceps, .middleBack]
        case .football:   return [.quadriceps, .hamstrings, .glutes, .calves, .abdominals]
        case .basketball: return [.quadriceps, .calves, .glutes, .shoulders, .abdominals]
        case .cycling:    return [.quadriceps, .hamstrings, .glutes, .calves, .abdominals]
        case .boxing:     return [.shoulders, .lats, .abdominals, .triceps, .calves]
        case .volleyball: return [.quadriceps, .calves, .shoulders, .glutes, .abdominals]
        case .other:      return []
        }
    }
}

enum Injury: String, Codable, CaseIterable, Identifiable, Sendable {
    case knee, shoulder, lowerBack, postInjuryRecovery
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .knee: return "Knee"
        case .shoulder: return "Shoulder"
        case .lowerBack: return "Lower back"
        case .postInjuryRecovery: return "Post-injury recovery"
        }
    }
    /// Muscle regions to avoid loading for this limitation.
    var avoidMuscles: [Muscle] {
        switch self {
        case .knee: return [.quadriceps, .hamstrings, .calves]
        case .shoulder: return [.shoulders]
        case .lowerBack: return [.lowerBack]
        case .postInjuryRecovery: return []
        }
    }
}

extension Equipment {
    /// The primary training equipment types offered as onboarding choices (bodyweight last).
    static let selectable: [Equipment] = [
        .barbell, .dumbbell, .machine, .cable, .kettlebells, .bands, .ezCurlBar, .bodyOnly
    ]
}

enum EquipmentAccess: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullGym, home, bodyweight
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fullGym: return "Full gym"
        case .home: return "Home (dumbbells)"
        case .bodyweight: return "Bodyweight only"
        }
    }
    /// The equipment types this access level permits.
    var allowedEquipment: Set<Equipment> {
        switch self {
        case .fullGym:
            return [.barbell, .dumbbell, .machine, .cable, .bodyOnly, .bands,
                    .kettlebells, .ezCurlBar, .exerciseBall, .foamRoll, .medicineBall, .other]
        case .home:
            return [.dumbbell, .bodyOnly, .bands, .kettlebells, .exerciseBall, .foamRoll, .medicineBall]
        case .bodyweight:
            return [.bodyOnly, .bands]
        }
    }
}

struct QuizAnswers: Equatable, Sendable {
    var firstName: String = ""
    var goal: Goal = .buildMuscle
    var sport: Sport? = nil
    /// Free-text sport name, used only when `sport == .other`.
    var customSport: String = ""
    var experience: Experience = .beginner
    var gender: Gender = .male
    var age: Int = 28
    /// Body height in centimetres (stored metric; display converts at the edge).
    var heightCm: Int = 175
    /// Body weight in kilograms (stored metric).
    var bodyWeightKg: Double = 75
    var daysPerWeek: Int = 3
    var minutesPerSession: Int = 45
    var injuries: Set<Injury> = []
    var equipment: EquipmentAccess = .fullGym
    /// Specific equipment types the user trains with. Empty means "use whatever my access
    /// level allows"; non-empty restricts the plan to exactly these types.
    var equipmentTypes: Set<Equipment> = []

    /// The equipment the plan may use — the chosen types, or the access level's default set.
    var allowedEquipment: Set<Equipment> {
        equipmentTypes.isEmpty ? equipment.allowedEquipment : equipmentTypes
    }

    /// Human-readable list of the equipment the plan may use (for the AI prompt & report).
    var equipmentDescription: String {
        let names = Equipment.selectable.filter { allowedEquipment.contains($0) }.map(\.displayName)
        return names.isEmpty ? equipment.displayName : names.joined(separator: ", ")
    }

    /// All muscle regions to avoid, derived from selected injuries.
    var avoidedMuscles: Set<Muscle> {
        Set(injuries.flatMap(\.avoidMuscles))
    }

    /// Trimmed first name, or empty if none given. (We only collect a first name.)
    var fullName: String {
        firstName.trimmingCharacters(in: .whitespaces)
    }

    /// Human-facing sport label: the free-text value when "Other", else the enum name.
    /// Empty when no sport applies.
    var sportLabel: String {
        guard let sport else { return "" }
        return sport == .other ? customSport.trimmingCharacters(in: .whitespaces) : sport.displayName
    }

    /// Body-mass index from height & weight, or nil if height is unset.
    var bmi: Double? {
        guard heightCm > 0 else { return nil }
        let m = Double(heightCm) / 100
        return bodyWeightKg / (m * m)
    }

    /// A plain-language BMI band used in the coach report.
    var bmiCategory: String? {
        guard let bmi else { return nil }
        switch bmi {
        case ..<18.5: return "underweight"
        case 18.5..<25: return "a healthy weight"
        case 25..<30: return "overweight"
        default: return "in the obese range"
        }
    }
}
