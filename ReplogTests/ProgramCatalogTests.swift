//
//  ProgramCatalogTests.swift
//  ReplogTests
//
//  Verifies the bundled program library loads, decodes leniently, and indexes correctly,
//  plus the MovementPattern enum's round-trip and the alternate schedule shapes.
//

import Testing
import Foundation
@testable import Replog

struct ProgramCatalogTests {

    // MARK: - Full-file decode

    @Test func bundledLibraryLoadsAll62Programs() {
        let catalog = ProgramCatalog(bundle: .main)
        #expect(catalog.all.count == 62)
        #expect(catalog.byID.count == 62)
    }

    @Test func everyProgramIdIsUnique() {
        let catalog = ProgramCatalog(bundle: .main)
        let ids = catalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyProgramHasNameAndAtLeastOneScheduleShape() {
        let catalog = ProgramCatalog(bundle: .main)
        for p in catalog.all {
            #expect(!p.name.isEmpty, "\(p.id) has empty name")
            // Every program prescribes work in one of the three shapes.
            let hasWork = !p.days.isEmpty || !p.weeklyStructure.isEmpty || !p.monthlyWave.isEmpty
            #expect(hasWork, "\(p.id) has no days / weeklyStructure / monthlyWave")
        }
    }

    @Test func filteredQueriesResolve() {
        let catalog = ProgramCatalog(bundle: .main)
        #expect(!catalog.programs(goal: "strength").isEmpty)
        #expect(catalog.programs(sport: "running").allSatisfy { $0.sport?.lowercased() == "running" })
        #expect(!catalog.programs(sport: "running").isEmpty)
        #expect(catalog.program(id: "does_not_exist") == nil)
    }

    // MARK: - Spot-checks of three known programs

    @Test func beginnerFullBodyFieldsAreCorrect() throws {
        let catalog = ProgramCatalog(bundle: .main)
        let p = try #require(catalog.program(id: "beginner_full_body_3d"))
        #expect(p.category == "strength")
        #expect(p.daysPerWeek == 3)
        #expect(p.durationWeeks == 12)
        #expect(p.audience.sex == .any)
        #expect(p.audience.experienceLevel == "beginner")
        #expect(p.audience.ageMin == 16)
        #expect(p.audience.ageMax == 55)
        #expect(p.equipmentRequired.contains("barbell"))
        #expect(!p.days.isEmpty)
        let firstSlot = try #require(p.days.first?.slots.first)
        #expect(firstSlot.pattern == .squat)
        #expect(firstSlot.sets == 3)
        #expect(firstSlot.reps == "5")
        #expect(firstSlot.restSeconds == 180)
        #expect(firstSlot.primaryMuscles.contains(.quadriceps))
    }

    @Test func couchTo5kUsesWeeklyStructure() throws {
        let catalog = ProgramCatalog(bundle: .main)
        let p = try #require(catalog.program(id: "couch_to_5k_9wk"))
        #expect(p.days.isEmpty)
        #expect(p.weeklyStructure.count == 9)
        #expect(p.weeklyStructure.first?.week == 1)
        // Weeks are in ascending order as authored.
        #expect(p.weeklyStructure.map(\.week) == Array(1...9))
        #expect(p.sport == "running")
    }

    @Test func fiveThreeOneUsesMonthlyWaveSortedByWeek() throws {
        let catalog = ProgramCatalog(bundle: .main)
        let p = try #require(catalog.program(id: "strength_531_style_4d"))
        #expect(p.monthlyWave.count == 4)
        // The wave object is flattened and sorted week1 < week2 < … regardless of JSON order.
        #expect(p.monthlyWave.map(\.label) == ["week1", "week2", "week3", "week4"])
        #expect(p.monthlyWave.last?.prescription.contains("deload") == true)
    }

    // MARK: - Lenient decoding against malformed fixtures

    @Test func decodesMinimalProgramWithOnlyIdAndName() throws {
        let json = #"[{ "id": "min", "name": "Minimal" }]"#.data(using: .utf8)!
        let programs = ProgramCatalog.decode(json)
        let p = try #require(programs.first)
        #expect(p.id == "min")
        #expect(p.name == "Minimal")
        #expect(p.category == "general_fitness")   // default
        #expect(p.goals.isEmpty)
        #expect(p.days.isEmpty)
        #expect(p.audience.sex == .any)
        #expect(p.medicalDisclaimer == nil)
        #expect(!p.requiresDisclaimerAcknowledgement)
    }

    @Test func programMissingIdIsDropped() {
        // The wrapper drops un-decodable elements rather than failing the whole file.
        let json = """
        { "programs": [
          { "name": "No ID here" },
          { "id": "ok", "name": "Fine" }
        ]}
        """.data(using: .utf8)!
        let programs = ProgramCatalog.decode(json)
        #expect(programs.map(\.id) == ["ok"])
    }

    @Test func unknownPatternDecodesToOther() throws {
        let json = """
        { "programs": [{
          "id": "x", "name": "X",
          "days": [{ "name": "D", "slots": [
            { "pattern": "moon_walk", "sets": 3, "reps": "5", "intensity": "hard" }
          ]}]
        }]}
        """.data(using: .utf8)!
        let programs = ProgramCatalog.decode(json)
        let slot = try #require(programs.first?.days.first?.slots.first)
        #expect(slot.pattern == .other("moon_walk"))
        #expect(slot.variant == nil)
        #expect(slot.restSeconds == nil)
    }

    @Test func unknownMusclesAreDroppedFromSlot() throws {
        let json = """
        { "programs": [{
          "id": "x", "name": "X",
          "days": [{ "name": "D", "slots": [
            { "pattern": "squat", "primaryMuscles": ["quads", "totally-made-up"],
              "sets": 3, "reps": "5", "intensity": "hard" }
          ]}]
        }]}
        """.data(using: .utf8)!
        let programs = ProgramCatalog.decode(json)
        let slot = try #require(programs.first?.days.first?.slots.first)
        // "quads" maps via Muscle.lenient; the nonsense value is dropped.
        #expect(slot.primaryMuscles == [.quadriceps])
    }

    @Test func unknownSexAndEmptyAgeRangeAreLenient() throws {
        let json = """
        { "programs": [{
          "id": "x", "name": "X",
          "audience": { "sex": "nonbinary_focused", "experienceLevel": "cosmic" }
        }]}
        """.data(using: .utf8)!
        let p = try #require(ProgramCatalog.decode(json).first)
        #expect(p.audience.sex == .other("nonbinary_focused"))
        #expect(p.audience.experienceLevel == "cosmic")
        #expect(p.audience.ageMin == nil)
        #expect(p.audience.admits(age: 30))   // missing range accepts all
    }

    @Test func bareTopLevelArrayIsAlsoAccepted() throws {
        let json = #"[{ "id": "a", "name": "A" }, { "id": "b", "name": "B" }]"#.data(using: .utf8)!
        let programs = ProgramCatalog.decode(json)
        #expect(programs.map(\.id) == ["a", "b"])
    }

    // MARK: - MovementPattern round-trip

    @Test func everyKnownPatternRoundTripsThroughRawValue() {
        for pattern in MovementPattern.known {
            #expect(MovementPattern(raw: pattern.rawValue) == pattern)
        }
    }

    @Test func patternRoundTripsThroughCodable() throws {
        let patterns: [MovementPattern] = MovementPattern.known + [.other("free_solo")]
        let data = try JSONEncoder().encode(patterns)
        let decoded = try JSONDecoder().decode([MovementPattern].self, from: data)
        #expect(decoded == patterns)
    }

    @Test func patternDecodingFoldsCaseAndWhitespace() {
        #expect(MovementPattern(raw: "  Horizontal_Push ") == .horizontalPush)
        #expect(MovementPattern(raw: "ROW_ERG") == .rowErg)
    }

    @Test func conditioningPatternsAreFlagged() {
        #expect(MovementPattern.run.isConditioningOrMobility)
        #expect(MovementPattern.stretchStatic.isConditioningOrMobility)
        #expect(!MovementPattern.squat.isConditioningOrMobility)
        #expect(!MovementPattern.horizontalPush.isConditioningOrMobility)
    }

    // MARK: - Audience age membership

    @Test func audienceAgeMembershipRespectsInclusiveBounds() {
        let a = ProgramAudience(ageRange: [16, 55])
        #expect(a.admits(age: 16))
        #expect(a.admits(age: 55))
        #expect(!a.admits(age: 15))
        #expect(!a.admits(age: 56))
    }

    // MARK: - Queries over an explicit library

    /// A small library built from JSON, so the queries are tested against known content
    /// rather than against whatever the bundled 62 happen to contain today.
    private func library() -> ProgramCatalog {
        let json = """
        { "programs": [
          { "id": "a", "name": "Starting Strength", "category": "strength",
            "goals": ["get_strong"], "sport": "running",
            "whoIsItFor": "Novices with a barbell.", "tags": ["barbell", "novice"] },
          { "id": "b", "name": "Hypertrophy Block", "category": "Hypertrophy",
            "goals": ["build_muscle"],
            "whoIsItFor": "Lifters chasing size.", "tags": ["dumbbell"] }
        ]}
        """.data(using: .utf8)!
        return ProgramCatalog(programs: ProgramCatalog.decode(json))
    }

    @Test func anExplicitLibraryIndexesItsProgramsById() {
        let catalog = library()
        #expect(catalog.all.count == 2)
        #expect(catalog.program(id: "b")?.name == "Hypertrophy Block")
        #expect(catalog.program(id: "nope") == nil)
    }

    @Test func categoryMatchingIgnoresCase() {
        // The library file is hand-maintained; "Hypertrophy" and "hypertrophy" are the
        // same category and must not split the results.
        #expect(library().programs(category: "hypertrophy").map(\.id) == ["b"])
        #expect(library().programs(category: "STRENGTH").map(\.id) == ["a"])
        #expect(library().programs(category: "nothing").isEmpty)
    }

    @Test func goalAndSportQueriesFilterOnTheirOwnFields() {
        #expect(library().programs(goal: "build_muscle").map(\.id) == ["b"])
        #expect(library().programs(sport: "RUNNING").map(\.id) == ["a"])
        #expect(library().programs(sport: "curling").isEmpty)
    }

    @Test func searchLooksAtTheName_theAudienceLine_andTheTags() {
        let catalog = library()
        #expect(catalog.search("strength").map(\.id) == ["a"])
        #expect(catalog.search("chasing size").map(\.id) == ["b"])
        #expect(catalog.search("BARBELL").map(\.id) == ["a"])
        #expect(catalog.search("nothing at all").isEmpty)
    }

    @Test func anEmptySearchIsNotAFilter() {
        #expect(library().search("").count == 2)
        #expect(library().search("   ").count == 2)
    }

    @Test func aDuplicateIdKeepsTheFirstDefinition() {
        let json = """
        { "programs": [{ "id": "a", "name": "First" }, { "id": "a", "name": "Second" }]}
        """.data(using: .utf8)!
        let catalog = ProgramCatalog(programs: ProgramCatalog.decode(json))
        #expect(catalog.all.count == 2)
        #expect(catalog.program(id: "a")?.name == "First")
    }

    @Test func malformedDataYieldsAnEmptyLibraryRatherThanThrowing() {
        #expect(ProgramCatalog.decode(Data("not json".utf8)).isEmpty)
        #expect(ProgramCatalog.decode(Data()).isEmpty)
    }

    // MARK: - ProgramSex round trip

    @Test func everyKnownSexTokenRoundTripsThroughItsRawValue() {
        for (raw, expected) in [("any", ProgramSex.any), ("female", .female),
                                ("female_focused", .femaleFocused),
                                ("male_focused", .maleFocused)] {
            #expect(ProgramSex(raw: raw) == expected)
            #expect(expected.rawValue == raw)
        }
    }

    @Test func anUnknownSexTokenIsKeptVerbatimAndSurvivesEncoding() throws {
        let sex = ProgramSex(raw: "  Nonbinary  ")
        #expect(sex == .other("nonbinary"))
        #expect(sex.rawValue == "nonbinary")

        // Encodes as a single string, so a re-encoded library is still readable.
        let data = try JSONEncoder().encode([sex])
        #expect(String(decoding: data, as: UTF8.self) == "[\"nonbinary\"]")
        #expect(try JSONDecoder().decode([ProgramSex].self, from: data) == [sex])
    }

    @Test func anEmptySexTokenMeansAnyone() {
        #expect(ProgramSex(raw: "") == .any)
    }

    // MARK: - Weekly structure

    @Test func aWeeklyStructureEntryCanBeBuiltDirectly() {
        let entry = WeeklyStructureEntry(week: 3, session: "Intervals")
        #expect(entry.week == 3)
        #expect(entry.session == "Intervals")
    }

    @Test func aMalformedWeeklyStructureEntryDecodesToEmptyRatherThanFailing() throws {
        let json = #"[{ "week": "three", "session": null }]"#.data(using: .utf8)!
        let entries = try JSONDecoder().decode([WeeklyStructureEntry].self, from: json)
        #expect(entries == [WeeklyStructureEntry(week: 0, session: "")])
    }
}
