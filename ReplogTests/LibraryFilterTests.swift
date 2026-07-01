//
//  LibraryFilterTests.swift
//  ReplogTests
//
//  The structured Library filter: AND across facets, OR within a facet, and the
//  catalog search that combines it with free-text matching.
//

import Testing
import Foundation
@testable import Replog

struct LibraryFilterTests {

    /// Builds a minimal catalog exercise for filter unit tests.
    private func makeExercise(
        id: String = "x",
        name: String = "Test Lift",
        force: Force? = .push,
        level: Level = .beginner,
        mechanic: Mechanic? = .compound,
        equipment: Equipment? = .barbell,
        primary: [Muscle] = [.chest],
        secondary: [Muscle] = [.triceps],
        category: ExerciseCategory = .strength
    ) -> Exercise {
        Exercise(id: id, name: name, force: force, level: level, mechanic: mechanic,
                 equipment: equipment, primaryMuscles: primary, secondaryMuscles: secondary,
                 category: category, instructions: [], images: [])
    }

    @Test func emptyFilterMatchesEverything() {
        let f = LibraryFilter()
        #expect(f.isEmpty)
        #expect(f.activeCount == 0)
        #expect(f.matches(makeExercise()))
    }

    @Test func singleFacetFiltersByThatValue() {
        var f = LibraryFilter()
        f.equipment = [.dumbbell]
        #expect(!f.matches(makeExercise(equipment: .barbell)))
        #expect(f.matches(makeExercise(equipment: .dumbbell)))
    }

    @Test func withinFacetIsOR() {
        var f = LibraryFilter()
        f.levels = [.beginner, .expert]
        #expect(f.matches(makeExercise(level: .beginner)))
        #expect(f.matches(makeExercise(level: .expert)))
        #expect(!f.matches(makeExercise(level: .intermediate)))
    }

    @Test func acrossFacetsIsAND() {
        var f = LibraryFilter()
        f.equipment = [.barbell]
        f.levels = [.expert]
        // Satisfies equipment but not level → excluded.
        #expect(!f.matches(makeExercise(level: .beginner, equipment: .barbell)))
        // Satisfies both → included.
        #expect(f.matches(makeExercise(level: .expert, equipment: .barbell)))
    }

    @Test func muscleFacetMatchesPrimaryOrSecondary() {
        var f = LibraryFilter()
        f.muscles = [.triceps]
        #expect(f.matches(makeExercise(primary: [.chest], secondary: [.triceps])))  // secondary hit
        #expect(f.matches(makeExercise(primary: [.triceps], secondary: [])))         // primary hit
        #expect(!f.matches(makeExercise(primary: [.chest], secondary: [.shoulders])))
    }

    @Test func muscleScopePrimaryOnlyIgnoresSecondary() {
        var f = LibraryFilter()
        f.muscles = [.triceps]
        f.muscleScope = .primary
        #expect(!f.matches(makeExercise(primary: [.chest], secondary: [.triceps])))  // secondary ignored
        #expect(f.matches(makeExercise(primary: [.triceps], secondary: [])))
        // Default scope still counts secondary movers.
        f.muscleScope = .anyRole
        #expect(f.matches(makeExercise(primary: [.chest], secondary: [.triceps])))
    }

    @Test func muscleFacetIsANDAcrossSelections() {
        var f = LibraryFilter()
        f.muscles = [.chest, .triceps]
        // Trains BOTH → included.
        #expect(f.matches(makeExercise(primary: [.chest], secondary: [.triceps])))
        // Trains only one of the two → excluded (AND, not OR).
        #expect(!f.matches(makeExercise(primary: [.chest], secondary: [.shoulders])))
        #expect(!f.matches(makeExercise(primary: [.triceps], secondary: [])))
    }

    @Test func nilEquipmentNeverMatchesAnEquipmentFacet() {
        var f = LibraryFilter()
        f.equipment = [.barbell]
        #expect(!f.matches(makeExercise(equipment: nil)))
    }

    @Test func activeCountSumsSelectedValues() {
        var f = LibraryFilter()
        f.levels = [.beginner, .expert]  // 2
        f.equipment = [.barbell]         // 1
        f.muscles = [.chest]             // 1
        #expect(f.activeCount == 4)
        #expect(!f.isEmpty)
    }
}

@MainActor
struct LibraryCatalogSearchTests {
    private let catalog = ExerciseCatalog(bundle: .main)

    @Test func filterConstrainsCatalogResults() {
        var f = LibraryFilter()
        f.equipment = [.barbell]
        f.levels = [.beginner]
        let results = catalog.search("", filter: f)
        #expect(!results.isEmpty)
        for ex in results {
            #expect(ex.equipment == .barbell)
            #expect(ex.level == .beginner)
        }
    }

    @Test func filterCombinesWithTextQuery() {
        var f = LibraryFilter()
        f.muscles = [.chest]
        let results = catalog.search("press", filter: f)
        #expect(!results.isEmpty)
        for ex in results {
            #expect(ex.name.localizedCaseInsensitiveContains("press"))
            let worked = Set(ex.primaryMuscles).union(ex.secondaryMuscles)
            #expect(worked.contains(.chest))
        }
    }

    @Test func emptyFilterAndQueryReturnsWholeCatalog() {
        #expect(catalog.search("", filter: LibraryFilter()).count == catalog.all.count)
    }
}

@MainActor
struct LibraryViewModelTests {
    @Test func toggleEquipmentAddsThenRemoves() {
        let vm = LibraryViewModel()
        vm.toggleEquipment(.cable)
        #expect(vm.filter.equipment == [.cable])
        vm.toggleEquipment(.cable)
        #expect(vm.filter.equipment.isEmpty)
    }

    @Test func clearFilterResetsEverything() {
        let vm = LibraryViewModel()
        vm.filter.levels = [.expert]
        vm.filter.muscles = [.lats]
        vm.clearFilter()
        #expect(vm.filter.isEmpty)
    }
}
