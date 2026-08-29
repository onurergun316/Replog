//
//  StoreModelsTests.swift
//  ReplogTests
//
//  The store's own layer: the singleton accessors, the check-in writers that are meant to
//  be one-per-day, custom exercises and what deleting one is allowed to destroy, and the
//  typed views the `@Model` classes put over their raw stored columns.
//
//  These are the paths every feature goes through and nothing owned — a wrong fallback on
//  an unknown raw value, or a second check-in inserting rather than replacing, is invisible
//  until it has been corrupting data for weeks.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct StoreModelsTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    // MARK: - Singletons

    @Test func theProfileAndSettingsAreCreatedOnceAndReused() {
        let ctx = makeContext()
        let profile = ctx.userProfile()
        profile.name = "Alex Fischer"
        let settings = ctx.appSettings()
        settings.restSeconds = 120
        try? ctx.save()

        #expect(ctx.userProfile().name == "Alex Fischer")
        #expect(ctx.appSettings().restSeconds == 120)
        #expect(((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).count == 1)
        #expect(((try? ctx.fetch(FetchDescriptor<AppSettings>())) ?? []).count == 1)
    }

    @Test func plansComeBackInDisplayOrder() {
        let ctx = makeContext()
        for (name, order) in [("Third", 2), ("First", 0), ("Second", 1)] {
            ctx.insert(Plan(name: name, order: order))
        }
        try? ctx.save()

        #expect(ctx.allPlans().map(\.name) == ["First", "Second", "Third"])
    }

    @Test func recomputingStreaksReadsTheScheduleAndTheDoneDays() {
        let ctx = makeContext()
        let plan = Plan(name: "PPL", order: 0)
        ctx.insert(plan)
        let today = Date()
        for offset in 0..<3 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let workout = Workout(name: "Day", day: Weekday.from(day), order: offset)
            workout.plan = plan
            ctx.insert(workout)
        }
        let profile = ctx.userProfile()
        profile.doneDates = (0..<3).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: today)
        }
        try? ctx.save()

        ctx.recomputeStreaks(profile: profile, today: today)
        #expect(profile.streak == 3)
    }

    // MARK: - Typed views over raw columns

    @Test func anUnknownStoredRawFallsBackRatherThanCrashing() {
        let profile = UserProfile(name: "Alex", goal: .buildMuscle)
        profile.goalRaw = "no-such-goal"
        #expect(profile.goal == .buildMuscle)

        let settings = AppSettings()
        settings.unitsRaw = "stones"
        #expect(settings.units == .kg)

        let readiness = ReadinessEntry(date: Date(), sleep: .poor, soreness: .good, stress: .good)
        readiness.sleepRaw = 99
        readiness.sorenessRaw = -1
        #expect(readiness.sleep == .good)
        #expect(readiness.soreness == .good)
    }

    @Test func profileGreetingsUseTheFirstNameOnly() {
        #expect(UserProfile(name: "Alex Fischer").firstName == "Alex")
        #expect(UserProfile(name: "Alex").firstName == "Alex")
        #expect(UserProfile(name: "").firstName == "there")
    }

    @Test func theAvatarInitialSurvivesWhitespaceAndEmptiness() {
        #expect(UserProfile(name: "  alex  ").initial == "A")
        #expect(UserProfile(name: "").initial == "?")
        #expect(UserProfile(name: "   ").initial == "?")
    }

    @Test func workoutStreakIsAnAliasForStreak() {
        let profile = UserProfile()
        profile.workoutStreak = 7
        #expect(profile.streak == 7)
        profile.streak = 3
        #expect(profile.workoutStreak == 3)
    }

    @Test func settingsUnitsRoundTripThroughTheirRawValue() {
        let settings = AppSettings()
        settings.units = .lb
        #expect(settings.unitsRaw == "lb")
        #expect(settings.units == .lb)
    }

    @Test func aReadinessRowExposesItsValueTypedCheckIn() {
        let entry = ReadinessEntry(date: Date(), sleep: .poor, soreness: .moderate, stress: .good)
        #expect(entry.checkIn == ReadinessCheckIn(sleep: .poor, soreness: .moderate, stress: .good))
    }

    // MARK: - One check-in per day

    @Test func asecondReadinessCheckInTheSameDayReplacesTheFirst() {
        let ctx = makeContext()
        let day = Date()
        ctx.logReadiness(ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .poor), date: day)
        ctx.logReadiness(ReadinessCheckIn(sleep: .good, soreness: .good, stress: .good), date: day)
        try? ctx.save()

        let all = (try? ctx.fetch(FetchDescriptor<ReadinessEntry>())) ?? []
        #expect(all.count == 1)
        #expect(all.first?.sleep == .good)
    }

    @Test func readinessOnAnotherDayIsItsOwnRow() {
        let ctx = makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ctx.logReadiness(ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good), date: yesterday)
        ctx.logReadiness(ReadinessCheckIn(sleep: .good, soreness: .good, stress: .good))
        try? ctx.save()

        #expect(((try? ctx.fetch(FetchDescriptor<ReadinessEntry>())) ?? []).count == 2)
    }

    @Test func recentReadinessIsWindowedAndNewestFirst() {
        let ctx = makeContext()
        for offset in [0, 2, 30] {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            ctx.logReadiness(ReadinessCheckIn(sleep: .good, soreness: .good, stress: .good), date: date)
        }
        try? ctx.save()

        let recent = ctx.recentReadiness(days: 7)
        #expect(recent.count == 2)
        #expect(recent.map(\.date) == recent.map(\.date).sorted(by: >))
    }

    @Test func asecondWeighInTheSameDayUpdatesRatherThanDuplicates() {
        let ctx = makeContext()
        ctx.logBodyweight(78.5)
        ctx.logBodyweight(78.1)
        try? ctx.save()

        #expect(ctx.bodyweightEntries().count == 1)
        #expect(ctx.latestBodyweight()?.weightKg == 78.1)
    }

    @Test func bodyweightEntriesAreOldestFirstAndTheLatestIsTheNewest() {
        let ctx = makeContext()
        for offset in [10, 3, 20] {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            ctx.logBodyweight(Double(80 - offset), date: date)
        }
        try? ctx.save()

        #expect(ctx.bodyweightEntries().map(\.date) == ctx.bodyweightEntries().map(\.date).sorted())
        #expect(ctx.latestBodyweight()?.weightKg == 77)
    }

    @Test func anEmptyStoreHasNoLatestBodyweight() {
        #expect(makeContext().latestBodyweight() == nil)
    }

    // MARK: - Custom exercises

    private func makeCustom(name: String = "Zercher Squat") -> CustomExercise {
        CustomExercise(name: name, force: .push, level: .intermediate, mechanic: .compound,
                       equipment: .barbell, primaryMuscles: [.quadriceps],
                       secondaryMuscles: [.glutes], category: .strength,
                       instructions: ["Rack it in the elbows.", "Stand up."],
                       imagesData: [Data([0x01])])
    }

    @Test func aCustomExerciseReadsBackAsACatalogEntry() {
        let custom = makeCustom()
        let exercise = custom.asExercise

        #expect(exercise.id == custom.id)
        #expect(exercise.name == "Zercher Squat")
        #expect(exercise.force == .push)
        #expect(exercise.level == .intermediate)
        #expect(exercise.mechanic == .compound)
        #expect(exercise.equipment == .barbell)
        #expect(exercise.primaryMuscles == [.quadriceps])
        #expect(exercise.secondaryMuscles == [.glutes])
        #expect(exercise.category == .strength)
        #expect(exercise.instructions.count == 2)
        // A custom exercise's photos are its own data, never bundled resource names.
        #expect(exercise.imageData == Data([0x01]))
        #expect(exercise.photos == [.data(Data([0x01]))])
    }

    @Test func unknownStoredFacetsDegradeToTheSafeDefault() {
        let custom = makeCustom()
        custom.forceRaw = "sideways"
        custom.levelRaw = "godlike"
        custom.mechanicRaw = "quantum"
        custom.equipmentRaw = "rocket"
        custom.categoryRaw = "vibes"
        custom.primaryMusclesRaw = ["chest", "not-a-muscle"]

        #expect(custom.force == nil)
        #expect(custom.level == .beginner)
        #expect(custom.mechanic == nil)
        #expect(custom.equipment == nil)
        #expect(custom.category == .strength)
        #expect(custom.primaryMuscles == [.chest])
    }

    @Test func aCustomExerciseGetsAUniqueIdByDefault() {
        #expect(makeCustom().id != makeCustom().id)
        #expect(makeCustom().id.hasPrefix("custom-"))
    }

    @Test func customExercisesComeBackNameSorted() {
        let ctx = makeContext()
        for name in ["Zercher Squat", "Anderson Squat", "Meadows Row"] {
            ctx.insert(makeCustom(name: name))
        }
        try? ctx.save()

        #expect(ctx.customExercises().map(\.name) == ["Anderson Squat", "Meadows Row", "Zercher Squat"])
    }

    @Test func lookingUpACustomExerciseByIdResolvesOrReturnsNil() {
        let ctx = makeContext()
        let custom = makeCustom()
        ctx.insert(custom)
        try? ctx.save()

        #expect(ctx.customExercise(id: custom.id)?.name == "Zercher Squat")
        #expect(ctx.customExercise(id: "Barbell_Bench_Press") == nil)
    }

    @Test func syncingMergesCustomExercisesIntoTheCatalog() {
        let ctx = makeContext()
        let custom = makeCustom()
        ctx.insert(custom)
        try? ctx.save()

        // An explicit catalog, so the shared one is not polluted for other tests.
        let catalog = ExerciseCatalog(exercises: [])
        ctx.syncCustomExercises(into: catalog)

        #expect(catalog.exercise(id: custom.id)?.name == "Zercher Squat")
        #expect(catalog.everything.map(\.name) == ["Zercher Squat"])
    }

    @Test func deletingACustomExercisePurgesPlansAndSessionsButKeepsHistory() throws {
        let ctx = makeContext()
        let custom = makeCustom()
        ctx.insert(custom)

        let plan = Plan(name: "PPL", order: 0)
        ctx.insert(plan)
        let workout = Workout(name: "Legs", day: .mon, order: 0)
        workout.plan = plan
        ctx.insert(workout)
        let item = PlanItem(exId: custom.id, order: 0)
        item.workout = workout
        ctx.insert(item)
        let template = SetTemplate(weightKg: 60, reps: 8, rpe: 8, order: 0)
        template.item = item
        ctx.insert(template)

        let session = ActiveSession(workoutId: workout.id, name: "Legs", planName: "PPL")
        ctx.insert(session)
        let sessionExercise = SessionExercise(exId: custom.id, order: 0)
        sessionExercise.session = session
        ctx.insert(sessionExercise)

        ctx.insert(HistoryEntry(exId: custom.id, date: Date(), topW: 60, topR: 8, e1rm: 76,
                                sets: [RecordedSet(w: 60, r: 8)]))
        try? ctx.save()

        ctx.deleteCustomExercise(custom)

        #expect(((try? ctx.fetch(FetchDescriptor<PlanItem>())) ?? []).isEmpty)
        #expect(((try? ctx.fetch(FetchDescriptor<SetTemplate>())) ?? []).isEmpty)
        #expect(((try? ctx.fetch(FetchDescriptor<SessionExercise>())) ?? []).isEmpty)
        #expect(((try? ctx.fetch(FetchDescriptor<CustomExercise>())) ?? []).isEmpty)
        // History is a factual record of training that happened — it stays.
        #expect(((try? ctx.fetch(FetchDescriptor<HistoryEntry>())) ?? []).count == 1)
    }

    // MARK: - History scoping

    @Test func unattributedHistoryIsExcludedFromAPlansTrail() {
        let ctx = makeContext()
        let planId = UUID()
        ctx.insert(HistoryEntry(exId: "Bench", date: Date(), topW: 60, topR: 8, e1rm: 76,
                                sets: [], planId: planId))
        ctx.insert(HistoryEntry(exId: "Bench", date: Date(), topW: 100, topR: 5, e1rm: 116,
                                sets: []))
        try? ctx.save()

        #expect(ctx.history(forExercise: "Bench").count == 2)
        #expect(ctx.history(forExercise: "Bench", inPlan: planId).count == 1)
        // No plan behind the question means no scope to respect.
        #expect(ctx.history(forExercise: "Bench", inPlan: nil).count == 2)
    }
}
