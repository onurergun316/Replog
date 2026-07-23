//
//  ProgressListFilterTests.swift
//  ReplogTests
//
//  Narrowing the trained-exercise lists inside Progress by name and primary muscle.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ProgressListFilterTests {

    private let catalog = ExerciseCatalog.shared
    private func lookup(_ id: String) -> Exercise? { catalog.exercise(id: id) }

    private let ids = ["Pushups", "Pullups", "Barbell_Bench_Press_-_Medium_Grip", "Crunches"]

    // MARK: - Query

    @Test func anInactiveFilterPassesEverythingThrough() {
        let filter = ProgressListFilter()
        #expect(!filter.isActive)
        #expect(filter.apply(to: ids, catalog: lookup) == ids)
    }

    @Test func nameSearchIsCaseInsensitive() throws {
        var filter = ProgressListFilter(query: "PULL")
        #expect(filter.apply(to: ids, catalog: lookup) == ["Pullups"])

        filter.query = "bench"
        #expect(filter.apply(to: ids, catalog: lookup) == ["Barbell_Bench_Press_-_Medium_Grip"])
    }

    @Test func whitespaceOnlyQueriesAreNotAFilter() {
        let filter = ProgressListFilter(query: "   ")
        #expect(!filter.isActive)
        #expect(filter.apply(to: ids, catalog: lookup) == ids)
    }

    @Test func aQueryMatchingNothingReturnsNothing() {
        let filter = ProgressListFilter(query: "zzzz")
        #expect(filter.apply(to: ids, catalog: lookup).isEmpty)
    }

    // MARK: - Muscle

    @Test func muscleFilterMatchesPrimaryMoversOnly() throws {
        // Push-ups train the chest as primary and the triceps as secondary. Asking for
        // chest work should not also return everything that incidentally uses it.
        let pushups = try #require(lookup("Pushups"))
        #expect(pushups.primaryMuscles.contains(.chest))
        #expect(pushups.secondaryMuscles.contains(.triceps))

        #expect(ProgressListFilter(muscle: .chest).matches(pushups))
        #expect(!ProgressListFilter(muscle: .triceps).matches(pushups))
    }

    @Test func queryAndMuscleBothHaveToMatch() throws {
        let filter = ProgressListFilter(query: "p", muscle: .lats)
        // "Pushups" matches the query but not the muscle; "Pullups" matches both.
        #expect(filter.apply(to: ids, catalog: lookup) == ["Pullups"])
    }

    // MARK: - Chip options

    @Test func onlyTrainedMusclesAreOffered() {
        let muscles = ProgressListFilter.availableMuscles(in: ids, catalog: lookup)
        #expect(Set(muscles) == [.chest, .lats, .abdominals])
        // Canonical enum order, not whatever order the ids arrived in.
        #expect(muscles == Muscle.allCases.filter(Set(muscles).contains))
    }

    @Test func noTrainedExercisesMeansNoChips() {
        #expect(ProgressListFilter.availableMuscles(in: [], catalog: lookup).isEmpty)
    }

    // MARK: - Unknown ids

    @Test func anUnknownExerciseSurvivesAnUnfilteredList() {
        // A catalog rebuild could retire an id; it must not silently vanish from history.
        let withGhost = ids + ["Retired_Movement"]
        #expect(ProgressListFilter().apply(to: withGhost, catalog: lookup) == withGhost)
        #expect(!ProgressListFilter(query: "p").apply(to: withGhost, catalog: lookup)
            .contains("Retired_Movement"))
    }
}
