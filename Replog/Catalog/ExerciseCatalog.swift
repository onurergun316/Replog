//
//  ExerciseCatalog.swift
//  Replog
//
//  Loads the bundled Free Exercise DB once and exposes fast lookups & filters.
//  This is the single source of truth for static exercise reference data.
//

import Foundation

/// In-memory index over the static exercise catalog.
/// Construct once (via `.shared`) and inject where needed.
/// `nonisolated` + immutable, so it is freely usable from any actor.
nonisolated final class ExerciseCatalog: Sendable {

    /// All bundled exercises, sorted by name (stable, case-insensitive).
    let all: [Exercise]
    /// Bundled exercises keyed by their stable `id`.
    let byID: [String: Exercise]

    /// User-created exercises, merged in at launch and whenever they change (`setCustom`).
    /// Guarded by a lock so the otherwise-immutable, nonisolated catalog stays Sendable —
    /// same technique as `ExerciseImageStore`'s cache.
    private nonisolated(unsafe) var customByID: [String: Exercise] = [:]
    private let customLock = NSLock()

    /// The app-wide instance, loaded from the main bundle.
    static let shared = ExerciseCatalog()

    /// Loads from `exercises.json` in the given bundle. Fails soft to an empty
    /// catalog if the resource is missing or malformed (e.g. in a misconfigured target).
    init(bundle: Bundle = .main) {
        let loaded = Self.load(from: bundle)
        self.all = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Test/seed initializer from an explicit array.
    init(exercises: [Exercise]) {
        self.all = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Custom exercises

    /// Replace the user-created layer. Call at launch and after any create/delete so the
    /// catalog resolves custom exercises everywhere it resolves bundled ones.
    func setCustom(_ exercises: [Exercise]) {
        customLock.lock(); defer { customLock.unlock() }
        customByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var customValues: [Exercise] {
        customLock.lock(); defer { customLock.unlock() }
        return Array(customByID.values)
    }

    /// Bundled + custom, name-sorted — the full set the user browses and searches.
    var everything: [Exercise] {
        (all + customValues).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Lookups

    func exercise(id: String) -> Exercise? {
        if let bundled = byID[id] { return bundled }
        customLock.lock(); defer { customLock.unlock() }
        return customByID[id]
    }

    /// Exercises whose primary OR secondary muscles include `muscle`.
    func exercises(forMuscle muscle: Muscle) -> [Exercise] {
        all.filter { $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle) }
    }

    /// Exercises usable with the given equipment set (`nil`-equipment counts as bodyweight).
    func exercises(equipment allowed: Set<Equipment>) -> [Exercise] {
        all.filter { ex in
            guard let eq = ex.equipment else { return true }
            return allowed.contains(eq)
        }
    }

    /// Library search/filter: free-text name match + optional equipment filter.
    /// `equipment == nil` means "All".
    func search(_ query: String, equipment: Equipment? = nil) -> [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return everything.filter { ex in
            let matchesEquip = equipment == nil || ex.equipment == equipment
            guard matchesEquip else { return false }
            guard !trimmed.isEmpty else { return true }
            return ex.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Library search/filter: free-text name match AND a structured multi-facet filter.
    func search(_ query: String, filter: LibraryFilter) -> [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return everything.filter { ex in
            guard filter.matches(ex) else { return false }
            guard !trimmed.isEmpty else { return true }
            return ex.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: Loading

    private static func load(from bundle: Bundle) -> [Exercise] {
        guard let url = bundle.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([Exercise].self, from: data)) ?? []
    }
}
