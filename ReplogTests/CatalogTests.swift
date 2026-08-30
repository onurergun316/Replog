//
//  CatalogTests.swift
//  ReplogTests
//
//  Verifies the bundled Free Exercise DB loads, parses leniently, and indexes correctly.
//

import Testing
import Foundation
@testable import Replog

struct CatalogTests {

    // MARK: Lenient decoding (no bundle needed)

    @Test func decodesEntryWithNoneAndNullFields() throws {
        let json = """
        [{
          "name": "Mystery Move",
          "force": "None",
          "level": "beginner",
          "mechanic": null,
          "equipment": "None",
          "primaryMuscles": ["chest", "totally-made-up"],
          "secondaryMuscles": [],
          "instructions": ["Do the thing."],
          "category": "strength",
          "images": ["Mystery_Move/0.jpg", "Mystery_Move/1.jpg"],
          "id": "Mystery_Move"
        }]
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode([Exercise].self, from: json)
        let ex = try #require(list.first)
        #expect(ex.force == nil)            // "None" -> nil
        #expect(ex.mechanic == nil)         // null -> nil
        #expect(ex.equipment == nil)        // "None" -> nil
        #expect(ex.primaryMuscles == [.chest]) // unknown muscle dropped
        #expect(ex.level == .beginner)
    }

    @Test func imageResourceNamesAreFlattened() throws {
        let json = """
        [{ "name":"X","level":"beginner","category":"strength",
           "primaryMuscles":[],"secondaryMuscles":[],"instructions":[],
           "images":["Battling_Ropes/0.jpg","Battling_Ropes/1.jpg"],"id":"Battling_Ropes" }]
        """.data(using: .utf8)!
        let ex = try #require(try JSONDecoder().decode([Exercise].self, from: json).first)
        #expect(ex.imageResourceNames == ["Battling_Ropes__0", "Battling_Ropes__1"])
    }

    // MARK: Bundle-backed catalog

    @Test func bundledCatalogLoadsFullDataset() {
        let catalog = ExerciseCatalog(bundle: .main)
        // The Free Exercise DB ships 873 entries.
        #expect(catalog.all.count == 873)
        #expect(catalog.byID.count == 873)
    }

    @Test func catalogIsSortedByName() {
        let catalog = ExerciseCatalog(bundle: .main)
        let names = catalog.all.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func lookupByIDResolves() {
        let catalog = ExerciseCatalog(bundle: .main)
        let benchID = "Barbell_Bench_Press_-_Medium_Grip"
        let ex = catalog.exercise(id: benchID)
        #expect(ex?.id == benchID)
        #expect(ex?.primaryMuscles.contains(.chest) == true)
    }

    @Test func searchFiltersByNameAndEquipment() {
        let catalog = ExerciseCatalog(bundle: .main)
        let press = catalog.search("bench press")
        #expect(press.allSatisfy { $0.name.localizedCaseInsensitiveContains("bench press") })
        #expect(!press.isEmpty)

        let barbellOnly = catalog.search("", equipment: .barbell)
        #expect(barbellOnly.allSatisfy { $0.equipment == .barbell })
        #expect(!barbellOnly.isEmpty)
    }

    @Test func equipmentFilterTreatsNilAsBodyweight() {
        let catalog = ExerciseCatalog(bundle: .main)
        let bodyweight = catalog.exercises(equipment: [.bodyOnly])
        // Entries with no recorded equipment are allowed through alongside body-only.
        #expect(bodyweight.allSatisfy { $0.equipment == nil || $0.equipment == .bodyOnly })
        #expect(!bodyweight.isEmpty)
    }

    @Test func everyExerciseHasResolvableImageName() {
        let catalog = ExerciseCatalog(bundle: .main)
        // Every catalog entry should yield at least one flattened image resource name.
        #expect(catalog.all.allSatisfy { !$0.imageResourceNames.isEmpty })
    }

    // MARK: Derived properties

    private func exercise(primary: [Muscle], secondary: [Muscle] = [],
                          images: [String] = [], imageDatas: [Data] = []) -> Exercise {
        Exercise(id: "X", name: "X", force: nil, level: .beginner, mechanic: nil,
                 equipment: nil, primaryMuscles: primary, secondaryMuscles: secondary,
                 category: .strength, instructions: [], images: images,
                 imageDatas: imageDatas)
    }

    @Test func allMusclesPutsPrimariesFirstAndDropsRepeats() {
        let ex = exercise(primary: [.chest, .triceps], secondary: [.triceps, .shoulders])
        #expect(ex.allMuscles == [.chest, .triceps, .shoulders])
    }

    @Test func allMusclesOfAMovementWithNoSecondariesIsJustThePrimaries() {
        #expect(exercise(primary: [.quadriceps]).allMuscles == [.quadriceps])
    }

    @Test func aBundledExerciseShowsItsShippedPhotos() {
        let ex = exercise(primary: [.chest], images: ["Bench/0.jpg", "Bench/1.jpg"])
        #expect(ex.photos == [.bundled("Bench__0"), .bundled("Bench__1")])
        #expect(ex.imageData == nil)
    }

    @Test func aCustomExercisesOwnPhotosWinOverAnythingBundled() {
        let ex = exercise(primary: [.chest], images: ["Bench/0.jpg"],
                          imageDatas: [Data([0x01]), Data([0x02])])
        #expect(ex.photos == [.data(Data([0x01])), .data(Data([0x02]))])
        #expect(ex.imageData == Data([0x01]))
    }

    @Test func photoIdentityDistinguishesBundledFromData() {
        // `ForEach` keys carousels on this, so a collision would drop a photo.
        #expect(ExercisePhoto.bundled("Bench__0").id == "bundled:Bench__0")
        #expect(ExercisePhoto.bundled("Bench__0").id != ExercisePhoto.bundled("Bench__1").id)
        #expect(ExercisePhoto.data(Data([0x01])).id.hasPrefix("data:"))
    }
}
