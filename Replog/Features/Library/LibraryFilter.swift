//
//  LibraryFilter.swift
//  Replog
//
//  A structured, multi-facet filter over the static catalog. Each facet is a set of
//  allowed values; a facet with an empty set imposes no constraint. An exercise
//  matches when it satisfies EVERY non-empty facet (AND across facets), and within a
//  facet any one selected value is enough (OR within a facet). Mirrors the Free
//  Exercise DB schema facets (see ../free-exercise-db-main/schema.json).
//

import Foundation
import Observation

/// Whether a muscle selection matches primary movers only, or primary + secondary.
enum MuscleScope: String, CaseIterable, Sendable {
    case anyRole    // primary OR secondary
    case primary    // primary only

    var label: String {
        switch self {
        case .anyRole: return "Primary + Secondary"
        case .primary: return "Primary only"
        }
    }
}

/// The user's active Library filter selection.
struct LibraryFilter: Equatable, Sendable {
    var levels: Set<Level> = []
    var equipment: Set<Equipment> = []
    var forces: Set<Force> = []
    var categories: Set<ExerciseCategory> = []
    var mechanics: Set<Mechanic> = []
    /// Muscles to match, subject to `muscleScope`.
    var muscles: Set<Muscle> = []
    /// Whether `muscles` match primary movers only, or primary + secondary.
    var muscleScope: MuscleScope = .anyRole

    var isEmpty: Bool {
        levels.isEmpty && equipment.isEmpty && forces.isEmpty
            && categories.isEmpty && mechanics.isEmpty && muscles.isEmpty
    }

    /// Number of individually selected facet values (drives the "Filters" badge).
    var activeCount: Int {
        levels.count + equipment.count + forces.count
            + categories.count + mechanics.count + muscles.count
    }

    /// Whether `exercise` satisfies all active facets. `nonisolated` so the nonisolated
    /// `ExerciseCatalog.search` can call it (the type is MainActor-isolated by default,
    /// but this is pure value logic over `Sendable` data).
    nonisolated func matches(_ exercise: Exercise) -> Bool {
        if !levels.isEmpty, !levels.contains(exercise.level) { return false }
        if !equipment.isEmpty {
            guard let eq = exercise.equipment, equipment.contains(eq) else { return false }
        }
        if !forces.isEmpty {
            guard let force = exercise.force, forces.contains(force) else { return false }
        }
        if !categories.isEmpty, !categories.contains(exercise.category) { return false }
        if !mechanics.isEmpty {
            guard let mech = exercise.mechanic, mechanics.contains(mech) else { return false }
        }
        if !muscles.isEmpty {
            // AND within the muscles facet: the exercise must train EVERY selected muscle,
            // in the role dictated by `muscleScope` (primary-only, or primary+secondary).
            let worked = muscleScope == .primary
                ? Set(exercise.primaryMuscles)
                : Set(exercise.primaryMuscles).union(exercise.secondaryMuscles)
            if !muscles.isSubset(of: worked) { return false }
        }
        return true
    }
}

/// Observable state for the Library screen: search text + structured filter.
@MainActor
@Observable
final class LibraryViewModel {
    var query = ""
    var filter = LibraryFilter()

    /// Catalog exercises matching the current search text and filter, in catalog order.
    func results(in catalog: ExerciseCatalog) -> [Exercise] {
        catalog.search(query, filter: filter)
    }

    /// Toggles a single equipment value (used by the quick-chip row).
    func toggleEquipment(_ equipment: Equipment) {
        if filter.equipment.contains(equipment) { filter.equipment.remove(equipment) }
        else { filter.equipment.insert(equipment) }
    }

    func clearFilter() { filter = LibraryFilter() }
}
