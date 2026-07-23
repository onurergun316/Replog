//
//  TemplateBackfillTests.swift
//  ReplogTests
//
//  Repairing plans whose sets were logged before finishing a workout wrote its numbers
//  back — and the belt-and-braces seeding that makes the live log correct even when no
//  write-back ever ran.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct TemplateBackfillTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    @discardableResult
    private func seedWorkout(_ ctx: ModelContext, sets: Int = 3) -> Workout {
        let plan = Plan(name: "PPL", order: 0); ctx.insert(plan)
        let workout = Workout(name: "Day 5", day: .fri, order: 0)
        workout.plan = plan; ctx.insert(workout)
        let item = PlanItem(exId: "Bench", order: 0); item.workout = workout; ctx.insert(item)
        for s in 0..<sets {
            let template = SetTemplate(weightKg: 50, reps: 10, rpe: 8, order: s, estimated: true)
            template.item = item; ctx.insert(template)
        }
        try? ctx.save()
        return workout
    }

    /// A session finished yesterday, before write-back existed: history was recorded,
    /// the plan was not updated.
    private func seedYesterdaysHistory(_ ctx: ModelContext) {
        let entry = HistoryEntry(
            exId: "Bench", date: Date().addingTimeInterval(-86_400),
            topW: 60, topR: 8, e1rm: Formulas.e1rmRounded(kg: 60, reps: 8),
            sets: [RecordedSet(w: 60, r: 8), RecordedSet(w: 60, r: 8), RecordedSet(w: 57.5, r: 7)])
        ctx.insert(entry); try? ctx.save()
    }

    // MARK: - The reported bug

    @Test func theLiveLogStartsFromLastSessionEvenWithoutAWriteBack() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedYesterdaysHistory(ctx)

        let session = SessionBuilder.start(workout: workout, into: ctx)
        let bench = session.exercises.first { $0.exId == "Bench" }!

        // The plan still says 50 x 10, but the athlete lifted 60 x 8 yesterday.
        #expect(bench.orderedSets.map(\.weightKg) == [60, 60, 57.5])
        #expect(bench.orderedSets.map(\.reps) == [8, 8, 7])
        // Seeded from real history, so it is no longer an estimate.
        #expect(bench.orderedSets.allSatisfy { !$0.estimated })
    }

    @Test func backfillUpdatesThePlanItself() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedYesterdaysHistory(ctx)

        let updated = TemplateBackfill.run(context: ctx)

        #expect(updated == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 60, 57.5])
        #expect(templates.map(\.reps) == [8, 8, 7])
        #expect(templates.allSatisfy { !$0.estimated })
    }

    @Test func backfillRunsOnlyOnce() throws {
        let ctx = makeContext()
        seedWorkout(ctx)
        seedYesterdaysHistory(ctx)

        #expect(TemplateBackfill.run(context: ctx) == 3)
        #expect(TemplateBackfill.run(context: ctx) == 0)   // flag set, never repeats
        #expect(ctx.appSettings().didBackfillTemplates)
    }

    // MARK: - What must not be overwritten

    @Test func aHandEditedTemplateIsNeverRewrittenFromHistory() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 1)
        seedYesterdaysHistory(ctx)
        // The athlete deliberately set 80 kg in the Workout Editor, which clears the flag.
        let template = workout.orderedItems[0].orderedSets[0]
        template.weightKg = 80
        template.estimated = false
        try ctx.save()

        TemplateBackfill.run(context: ctx)
        #expect(template.weightKg == 80)

        // And the live log respects it rather than reverting to yesterday's 60 kg.
        let session = SessionBuilder.start(workout: workout, into: ctx)
        #expect(session.exercises.first!.orderedSets[0].weightKg == 80)
    }

    @Test func aTemplateAlreadyWrittenByAFinishedSessionWins() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 1)
        // Two sessions: an older one at 60, and a newer one whose write-back set 70.
        seedYesterdaysHistory(ctx)
        let template = workout.orderedItems[0].orderedSets[0]
        template.weightKg = 70
        template.estimated = false          // write-back cleared it
        try ctx.save()

        TemplateBackfill.run(context: ctx)
        #expect(template.weightKg == 70)
    }

    @Test func noHistoryLeavesTheGeneratorsEstimateAlone() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)

        #expect(TemplateBackfill.run(context: ctx) == 0)
        #expect(workout.orderedItems[0].orderedSets.allSatisfy { $0.weightKg == 50 })

        // And a first-ever session still shows the "est" badge.
        let session = SessionBuilder.start(workout: workout, into: ctx)
        #expect(session.exercises.first!.orderedSets.allSatisfy { $0.estimated })
    }

    @Test func moreTemplatesThanLoggedSetsKeepsTheSurplusAsASeed() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 4)     // plan prescribes four
        seedYesterdaysHistory(ctx)                  // only three were logged

        #expect(TemplateBackfill.run(context: ctx) == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 60, 57.5, 50])
        #expect(templates[3].estimated)             // never logged against
    }
}
