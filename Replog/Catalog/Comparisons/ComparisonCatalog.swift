//
//  ComparisonCatalog.swift
//  Replog
//
//  Loads the bundled comparison library once and exposes it by family.
//  Mirrors `ProgramCatalog`: nonisolated, immutable, Sendable, fails soft to empty.
//
//  Failing soft matters more here than anywhere else in the app: this data only decorates
//  a number the athlete has already earned. If the file is missing, every caller simply
//  gets nil and the plain total is shown.
//

import Foundation

nonisolated final class ComparisonCatalog: Sendable {

    /// Inanimate reference masses, ascending.
    let objects: [WeightComparison]
    /// Animal body masses, ascending.
    let animals: [WeightComparison]
    /// Animal force figures, ascending.
    let strength: [WeightComparison]

    /// The app-wide instance, loaded from the main bundle.
    static let shared = ComparisonCatalog()

    /// Loads from `comparisons.json` in the given bundle. Empty on missing/malformed data.
    init(bundle: Bundle = .main) {
        let library = Self.load(from: bundle)
        objects = library.objects.sorted { $0.kg < $1.kg }
        animals = library.animals.sorted { $0.kg < $1.kg }
        strength = library.strength.sorted { $0.kg < $1.kg }
    }

    /// A catalog with nothing in it. Every caller treats this as "say nothing", which is
    /// what makes the whole feature safe to fail.
    static let empty = ComparisonCatalog(objects: [], animals: [], strength: [])

    /// Test/seed initializer from explicit rows. Note this needs at least one argument:
    /// a bare `ComparisonCatalog()` is the bundle-loading initializer above, not an empty
    /// one — use `.empty` when that is what you mean.
    init(objects: [WeightComparison] = [], animals: [WeightComparison] = [],
         strength: [WeightComparison] = []) {
        self.objects = objects.sorted { $0.kg < $1.kg }
        self.animals = animals.sorted { $0.kg < $1.kg }
        self.strength = strength.sorted { $0.kg < $1.kg }
    }

    /// Everything that is a mass rather than a force — what a tonnage compares against.
    var masses: [WeightComparison] { (objects + animals).sorted { $0.kg < $1.kg } }

    /// Force figures for one way of producing force.
    func strength(mode: ComparisonMode) -> [WeightComparison] {
        strength.filter { $0.mode == mode }
    }

    /// Force figures that suit how the athlete's own volume was produced. Pressing is
    /// raising a load, so it compares against animals lifting; rowing and pulling compare
    /// against animals hauling. `static` holds have no animal analogue worth claiming.
    func strength(for force: Force) -> [WeightComparison] {
        switch force {
        case .push:   return strength(mode: .lift)
        case .pull:   return strength(mode: .pull)
        case .static: return []
        }
    }

    var isEmpty: Bool { objects.isEmpty && animals.isEmpty && strength.isEmpty }

    private static func load(from bundle: Bundle) -> ComparisonLibrary {
        for candidate in bundles(preferring: bundle) {
            guard let url = candidate.url(forResource: "comparisons", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let library = try? JSONDecoder().decode(ComparisonLibrary.self, from: data) else {
                continue
            }
            return library
        }
        return ComparisonLibrary()
    }

    /// Where to look for the file. The app ships it in the main bundle; a SwiftPM build of
    /// the logic layer (how the suite runs off-device) puts it in the module's own bundle.
    /// Trying both means the same tests exercise the real data in either place.
    private static func bundles(preferring bundle: Bundle) -> [Bundle] {
        var candidates = [bundle, Bundle(for: ComparisonCatalog.self)]
        #if SWIFT_PACKAGE
        candidates.append(.module)
        #endif
        return candidates
    }
}

