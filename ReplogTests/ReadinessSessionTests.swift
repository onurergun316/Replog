//
//  ReadinessSessionTests.swift
//  ReplogTests
//
//  Verifies the readiness modulation applied by SessionBuilder: high fatigue trims the last
//  set of each exercise and records a note; the skip path (no check-in) leaves the session
//  exactly as prescribed.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct ReadinessSessionTests {

    /// A plan with one workout of two 3-set exercises in a fresh in-memory store.
    private func makeWorkout() -> (ModelContext, Workout) {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let plan = PlanFactory.emptyPlan(name: "P", into: context, order: 0)
        let workout = PlanFactory.addWorkout(to: plan, into: context)
        PlanFactory.addExercise("Barbell_Squat", to: workout, into: context)   // 3 sets
        PlanFactory.addExercise("Barbell_Bench_Press", to: workout, into: context) // 3 sets
        try? context.save()
        return (context, workout)
    }

    @Test func skipPathLeavesTheSessionUntouched() throws {
        let (context, workout) = makeWorkout()
        let session = SessionBuilder.start(workout: workout, into: context, readiness: nil)
        try context.save()

        #expect(session.readinessNote.isEmpty)
        #expect(session.exercises.count == 2)
        #expect(session.exercises.allSatisfy { $0.sets.count == 3 })
    }

    @Test func normalReadinessDoesNotTrimAndLeavesNoNote() throws {
        let (context, workout) = makeWorkout()
        let session = SessionBuilder.start(workout: workout, into: context, readiness: .fresh)
        try context.save()

        #expect(session.exercises.allSatisfy { $0.sets.count == 3 })
        #expect(session.readinessNote.isEmpty)   // normal modulation → nothing to explain
    }

    @Test func moderateReadinessCapsIntensityWithoutTrimming() throws {
        let (context, workout) = makeWorkout()
        let checkIn = ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good) // load 2
        let session = SessionBuilder.start(workout: workout, into: context, readiness: checkIn)
        try context.save()

        #expect(session.exercises.allSatisfy { $0.sets.count == 3 })   // volume kept
        #expect(!session.readinessNote.isEmpty)
        #expect(session.readinessNote.contains("Capped intensity"))
    }

    @Test func highFatigueTrimsTheLastSetOfEachExerciseAndNotes() throws {
        let (context, workout) = makeWorkout()
        let wrecked = ReadinessCheckIn(sleep: .poor, soreness: .poor, stress: .poor) // load 6
        let session = SessionBuilder.start(workout: workout, into: context, readiness: wrecked)
        try context.save()

        #expect(session.exercises.count == 2)
        #expect(session.exercises.allSatisfy { $0.sets.count == 2 })   // last set trimmed
        #expect(session.readinessNote.contains("Trimmed a set"))

        // The trimmed sets are actually removed from the store, not just detached.
        let remaining = try context.fetch(FetchDescriptor<LoggedSet>())
        #expect(remaining.count == 4)   // 2 exercises × 2 sets
    }

    @Test func loggingAReadinessCheckInPersistsOnePerDay() throws {
        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        context.logReadiness(ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good), date: day)
        context.logReadiness(ReadinessCheckIn(sleep: .good, soreness: .poor, stress: .good), date: day)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<ReadinessEntry>())
        #expect(entries.count == 1)                    // same day → overwrite
        #expect(entries.first?.soreness == .poor)      // latest values win
    }
}
