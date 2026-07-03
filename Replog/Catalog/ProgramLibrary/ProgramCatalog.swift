//
//  ProgramCatalog.swift
//  Replog
//
//  Loads the bundled program library once and exposes lookups & filtered queries.
//  Mirrors `ExerciseCatalog`: `nonisolated`, immutable, `Sendable`, fails soft to empty.
//
//  The library file is `{"programs": [...]}` with optional batch metadata; historically the
//  programs arrived in batches, so the loader also tolerates a bare top-level array and
//  batch elements that themselves nest a `{"programs": [...]}` object.
//

import Foundation

/// In-memory index over the static program library. Construct once (via `.shared`).
nonisolated final class ProgramCatalog: Sendable {

    /// All programs, in file order (curated ordering is meaningful).
    let all: [WorkoutProgram]
    /// Programs keyed by their stable `id`.
    let byID: [String: WorkoutProgram]

    /// The app-wide instance, loaded from the main bundle.
    static let shared = ProgramCatalog()

    /// Loads from `programs.json` in the given bundle. Empty catalog on missing/malformed data.
    init(bundle: Bundle = .main) {
        let loaded = Self.load(from: bundle)
        self.all = loaded
        self.byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Test/seed initializer from an explicit array.
    init(programs: [WorkoutProgram]) {
        self.all = programs
        self.byID = Dictionary(programs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Lookups & queries

    func program(id: String) -> WorkoutProgram? { byID[id] }

    /// Programs whose `goals` include the given goal token.
    func programs(goal: String) -> [WorkoutProgram] {
        all.filter { $0.goals.contains(goal) }
    }

    /// Programs whose `category` matches (case-insensitive).
    func programs(category: String) -> [WorkoutProgram] {
        all.filter { $0.category.caseInsensitiveCompare(category) == .orderedSame }
    }

    /// Programs tagged for a given sport (case-insensitive), e.g. "running".
    func programs(sport: String) -> [WorkoutProgram] {
        all.filter { $0.sport?.caseInsensitiveCompare(sport) == .orderedSame }
    }

    /// Free-text search over name, whoIsItFor, and tags.
    func search(_ query: String) -> [WorkoutProgram] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { p in
            p.name.localizedCaseInsensitiveContains(trimmed)
                || p.whoIsItFor.localizedCaseInsensitiveContains(trimmed)
                || p.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    // MARK: Loading

    /// Decodes the library, tolerating either a top-level array or a `{"programs": [...]}`
    /// wrapper, including batch elements that nest their own `programs` array.
    static func decode(_ data: Data) -> [WorkoutProgram] {
        let decoder = JSONDecoder()
        // Preferred shape: the merged library object.
        if let wrapper = try? decoder.decode(LibraryWrapper.self, from: data) {
            return wrapper.programs
        }
        // Fallback: a bare array of programs.
        if let array = try? decoder.decode([FlexibleProgram].self, from: data) {
            return array.flatMap(\.programs)
        }
        return []
    }

    private static func load(from bundle: Bundle) -> [WorkoutProgram] {
        guard let url = bundle.url(forResource: "programs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return decode(data)
    }
}

// MARK: - Wrapper decoding

/// The merged library file: `{"programs": [ ... ]}`. Batch metadata (schemaVersion, notes)
/// is ignored. Each element may itself be a program or a nested batch of programs.
private nonisolated struct LibraryWrapper: Decodable {
    let programs: [WorkoutProgram]

    enum CodingKeys: String, CodingKey { case programs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let elements = (try? c.decodeIfPresent([FlexibleProgram].self, forKey: .programs)) ?? []
        programs = elements.flatMap(\.programs)
    }
}

/// A library element that is either a single `WorkoutProgram` or a nested batch wrapper.
/// Decoding tries the program first, then the wrapper, so malformed entries drop silently
/// without failing the whole file.
private nonisolated struct FlexibleProgram: Decodable {
    let programs: [WorkoutProgram]

    init(from decoder: Decoder) throws {
        if let program = try? WorkoutProgram(from: decoder) {
            programs = [program]
        } else if let nested = try? decoder.container(keyedBy: LibraryWrapper.CodingKeys.self),
                  let batch = try? nested.decode([FlexibleProgram].self, forKey: .programs) {
            programs = batch.flatMap(\.programs)
        } else {
            programs = []
        }
    }
}
