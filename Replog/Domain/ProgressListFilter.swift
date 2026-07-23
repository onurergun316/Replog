//
//  ProgressListFilter.swift
//  Replog
//
//  Narrowing the exercise lists inside Progress: a name query plus an optional muscle.
//
//  Deliberately lighter than `LibraryFilter`. Library searches 873 exercises across six
//  facets with AND-across-facets and a primary/secondary scope toggle; Progress lists
//  only the handful you have actually trained, where that machinery would be ceremony.
//  Matching a *primary* muscle is the right question here — "show me my back work" —
//  rather than anything that incidentally involves the muscle.
//

import Foundation

struct ProgressListFilter: Equatable {
    var query: String = ""
    /// `nil` = every muscle.
    var muscle: Muscle?

    var isActive: Bool { !trimmedQuery.isEmpty || muscle != nil }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case- and diacritic-insensitive name match, plus the primary-muscle gate.
    func matches(_ exercise: Exercise) -> Bool {
        if let muscle, !exercise.primaryMuscles.contains(muscle) { return false }
        let needle = trimmedQuery
        guard !needle.isEmpty else { return true }
        return exercise.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Filters ids through the catalog. An id with no catalog entry is dropped only when
    /// a filter is actually active, so an unknown exercise never silently vanishes from
    /// an unfiltered list.
    func apply(to exIds: [String], catalog: (String) -> Exercise?) -> [String] {
        guard isActive else { return exIds }
        return exIds.filter { id in
            guard let exercise = catalog(id) else { return false }
            return matches(exercise)
        }
    }

    /// The primary muscles actually present in `exIds`, in the app's canonical order —
    /// so the chip row only ever offers muscles the athlete has trained.
    static func availableMuscles(in exIds: [String], catalog: (String) -> Exercise?) -> [Muscle] {
        var present: Set<Muscle> = []
        for id in exIds { present.formUnion(catalog(id)?.primaryMuscles ?? []) }
        return Muscle.allCases.filter(present.contains)
    }
}
