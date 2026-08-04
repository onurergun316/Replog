//
//  VolumeNarratorTests.swift
//  ReplogTests
//
//  Turning a tonnage into a picture. The rules that make the output feel written: a count
//  you can actually see, a reference that grows with the athlete, variety across seeds,
//  and honesty about how well attested an animal strength figure is.
//

import Testing
import Foundation
@testable import Replog

struct VolumeNarratorTests {

    private func mass(_ id: String, _ kg: Double, plural: String? = nil) -> WeightComparison {
        WeightComparison(id: id, singular: "a \(id)", plural: plural ?? "\(id)s", kg: kg,
                         family: .object, mode: nil, load: .lift, confidence: .measured,
                         note: "", source: "")
    }

    private func force(_ id: String, _ kg: Double, mode: ComparisonMode,
                       load: ComparisonLoad = .lift,
                       confidence: ComparisonConfidence = .measured) -> WeightComparison {
        WeightComparison(id: id, singular: "a \(id)'s strength", plural: "\(id)s' strength",
                         kg: kg, family: .strength, mode: mode, load: load,
                         confidence: confidence, note: "", source: "")
    }

    /// A spread wide enough that the picker has to choose rather than take the only option.
    private var catalog: ComparisonCatalog {
        ComparisonCatalog(objects: [mass("keg", 72), mass("car", 1750),
                                    mass("bus", 12700), mass("jet", 79000)],
                          animals: [mass("panda", 100), mass("elephant", 6000)],
                          strength: [force("gorilla", 530, mode: .lift, confidence: .estimated),
                                     force("chimp", 221, mode: .lift),
                                     force("ox", 2801, mode: .pull, load: .sled)])
    }

    // MARK: - Picking a count you can see

    @Test func theReferenceGrowsWithTheAthlete() {
        // A first session is kegs; a serious block is cars; a year is jets.
        #expect(VolumeNarrator.tonnage(kg: 400, catalog: catalog)?.id == "keg")
        #expect(VolumeNarrator.tonnage(kg: 9_000, catalog: catalog)?.id == "car")
        #expect(VolumeNarrator.tonnage(kg: 400_000, catalog: catalog)?.id == "jet")
    }

    @Test func aCountBelowOneIsNeverOffered() {
        // 500 kg against a 12,700 kg bus is 0.04 buses, which reads as a put-down.
        let onlyBus = ComparisonCatalog(objects: [mass("bus", 12700)])
        #expect(VolumeNarrator.tonnage(kg: 500, catalog: onlyBus) == nil)
    }

    @Test func anAbsurdCountIsNeverOffered() {
        // 900,000 washing machines is arithmetic, not a picture.
        let onlyKeg = ComparisonCatalog(objects: [mass("keg", 72)])
        #expect(VolumeNarrator.tonnage(kg: 65_000_000, catalog: onlyKeg) == nil)
    }

    @Test func nothingIsClaimedForNoWork() {
        #expect(VolumeNarrator.tonnage(kg: 0, catalog: catalog) == nil)
        #expect(VolumeNarrator.tonnage(kg: -50, catalog: catalog) == nil)
        #expect(VolumeNarrator.tonnageSentence(kg: 0, catalog: catalog) == nil)
    }

    @Test func anEmptyLibraryIsSilentRatherThanWrong() {
        let empty = ComparisonCatalog.empty
        #expect(empty.isEmpty)
        #expect(VolumeNarrator.tonnage(kg: 5_000, catalog: empty) == nil)
        #expect(VolumeNarrator.strengthSentence(kg: 5_000, force: .push, catalog: empty) == nil)
    }

    @Test func aCountInTheIdealBandScoresBest() {
        #expect(VolumeNarrator.score(for: 3) == 1)
        #expect(VolumeNarrator.score(for: 12) == 1)
        // Outside the band the score falls off but never goes negative.
        #expect(VolumeNarrator.score(for: 40) < 1)
        #expect(VolumeNarrator.score(for: 40) >= 0)
        #expect(VolumeNarrator.score(for: 1) < 1)
        #expect(VolumeNarrator.score(for: 0) == 0)
    }

    // MARK: - Phrasing

    @Test func theCountAndTheNounAgree() {
        let one = VolumeNarrator.comparison(forKg: 1750 * 1.6, among: [mass("car", 1750)])
        #expect(one?.count == 2)
        #expect(one?.phrase == "2 cars")

        let singular = VolumeNarrator.comparison(forKg: 1750 * 1.2, among: [mass("car", 1750)])
        #expect(singular?.count == 1)
        #expect(singular?.phrase == "a car")   // rounds to one, so the article is used
    }

    @Test func aRoundedCountIsHedgedAndAnExactOneIsNot() {
        let exact = VolumeNarrator.comparison(forKg: 1750 * 3, among: [mass("car", 1750)])
        #expect(exact?.sentence == "That is 3 cars.")
        let approximate = VolumeNarrator.comparison(forKg: 1750 * 3.4, among: [mass("car", 1750)])
        #expect(approximate?.sentence == "That is about 3 cars.")
    }

    @Test func theTonnageSentenceReadsAsACompliment() {
        let sentence = VolumeNarrator.tonnageSentence(kg: 1750 * 3, catalog: catalog)
        #expect(sentence == "That is 3 cars lifted off the floor.")
    }

    // MARK: - Variety without randomness

    @Test func theSameSeedAlwaysGivesTheSameAnswer() {
        let first = VolumeNarrator.tonnage(kg: 9_000, catalog: catalog, seed: 7)
        let second = VolumeNarrator.tonnage(kg: 9_000, catalog: catalog, seed: 7)
        #expect(first == second)
    }

    @Test func differentSeedsRotateBetweenEquallyGoodReferences() {
        // Two references that both give a count inside the ideal band, so both are fair.
        let tied = [mass("car", 1000), mass("van", 1000)]
        let picks = Set((0..<6).compactMap { VolumeNarrator.comparison(forKg: 4_000, among: tied, seed: $0)?.id })
        #expect(picks == ["car", "van"])
    }

    @Test func aNegativeSeedDoesNotTrap() {
        #expect(VolumeNarrator.tonnage(kg: 9_000, catalog: catalog, seed: -3) != nil)
    }

    @Test func theSeedIsStablePerDayAndMovesBetweenDays() {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let sameDayLater = day.addingTimeInterval(60 * 60)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        #expect(VolumeNarrator.seed(for: day, calendar: cal)
                == VolumeNarrator.seed(for: sameDayLater, calendar: cal))
        #expect(VolumeNarrator.seed(for: day, calendar: cal)
                != VolumeNarrator.seed(for: day.addingTimeInterval(86_400 * 3), calendar: cal))
    }

    // MARK: - Animal strength, honestly

    @Test func pressingComparesAgainstLiftingAndPullingAgainstHauling() {
        #expect(catalog.strength(for: .push).map(\.id).sorted() == ["chimp", "gorilla"])
        #expect(catalog.strength(for: .pull).map(\.id) == ["ox"])
        // A static hold has no animal analogue worth claiming.
        #expect(catalog.strength(for: .static).isEmpty)
    }

    @Test func anUnverifiedFigureIsHedged() {
        // The gorilla number is an estimate, so the copy says so.
        let sentence = VolumeNarrator.strengthSentence(kg: 530 * 3, force: .push,
                                                       catalog: catalog, seed: 1)
        #expect(sentence?.contains("roughly") == true)
        #expect(sentence?.hasPrefix("You pressed the equivalent of") == true)
    }

    @Test func aMeasuredFigureIsStatedPlainly() {
        let onlyChimp = ComparisonCatalog(strength: [force("chimp", 221, mode: .lift)])
        let sentence = VolumeNarrator.strengthSentence(kg: 221 * 4, force: .push, catalog: onlyChimp)
        #expect(sentence == "You pressed the equivalent of 4 chimps' strength.")
    }

    // MARK: - The bundled library itself

    @Test func theBundledLibraryIsUsable() throws {
        let catalog = ComparisonCatalog.shared
        try #require(!catalog.isEmpty, "comparisons.json failed to load")

        #expect(catalog.objects.count >= 20, "the brief asked for at least 20 objects")
        #expect(catalog.animals.count >= 10, "the brief asked for at least 10 animals")
        #expect(catalog.strength.count >= 10)

        // Every row has to be usable arithmetic and readable copy.
        for item in catalog.objects + catalog.animals + catalog.strength {
            #expect(item.kg > 0, "\(item.id) has no mass")
            #expect(!item.singular.isEmpty && !item.plural.isEmpty, "\(item.id) has no noun")
            #expect(!item.source.isEmpty, "\(item.id) is unsourced")
        }
        // Ids are unique, so a rotation can't pick the same thing twice.
        let ids = (catalog.objects + catalog.animals + catalog.strength).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func theBundledLibraryCoversEveryRealisticTotal() throws {
        let catalog = ComparisonCatalog.shared
        try #require(!catalog.isEmpty)

        // A first session through a decade of training: every one should find a picture.
        for kg in [2_000.0, 6_074, 25_000, 120_000, 500_000, 2_500_000, 12_000_000] {
            #expect(VolumeNarrator.tonnage(kg: kg, catalog: catalog) != nil,
                    "no comparison for \(kg) kg")
        }
    }

    @Test func theBundledStrengthLibraryCoversBothDirections() throws {
        let catalog = ComparisonCatalog.shared
        try #require(!catalog.isEmpty)
        #expect(!catalog.strength(for: .push).isEmpty)
        #expect(!catalog.strength(for: .pull).isEmpty)
        // A sled load must never be phrased as a lift.
        for item in catalog.strength where item.load == .sled {
            #expect(!item.singular.contains("lifting"), "\(item.id) calls a dragged load a lift")
        }
    }
}
