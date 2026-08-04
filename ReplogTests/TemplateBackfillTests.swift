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
            // Deliberately NOT flagged `estimated` — this is how PlanFactory.addExercise
            // and the editor's "add set" create them, and gating the carry-forward on that
            // flag is exactly why it silently did nothing on a real plan.
            let template = SetTemplate(weightKg: 50, reps: 10, rpe: 8, order: s)
            template.item = item; ctx.insert(template)
        }
        try? ctx.save()
        return workout
    }

    /// A session finished yesterday, before write-back existed: history was recorded,
    /// the plan was not updated. Attributed to `workout`'s plan, because history only
    /// speaks for the plan it was trained under (see `history(forExercise:inPlan:)`).
    private func seedYesterdaysHistory(_ ctx: ModelContext, in workout: Workout? = nil) {
        let entry = HistoryEntry(
            exId: "Bench", date: Date().addingTimeInterval(-86_400),
            topW: 60, topR: 8, e1rm: Formulas.e1rmRounded(kg: 60, reps: 8),
            sets: [RecordedSet(w: 60, r: 8), RecordedSet(w: 60, r: 8), RecordedSet(w: 57.5, r: 7)],
            workoutId: workout?.id, planId: workout?.plan?.id)
        ctx.insert(entry); try? ctx.save()
    }

    // MARK: - The reported bug

    @Test func theLiveLogStartsFromLastSessionEvenWithoutAWriteBack() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedYesterdaysHistory(ctx, in: workout)

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
        seedYesterdaysHistory(ctx, in: workout)

        let updated = TemplateBackfill.run(context: ctx)

        #expect(updated == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 60, 57.5])
        #expect(templates.map(\.reps) == [8, 8, 7])
        #expect(templates.allSatisfy { !$0.estimated })
    }

    @Test func backfillRunsOnlyOnce() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)
        seedYesterdaysHistory(ctx, in: workout)

        #expect(TemplateBackfill.run(context: ctx) == 3)
        #expect(TemplateBackfill.run(context: ctx) == 0)   // version recorded, never repeats
        #expect(ctx.appSettings().templateBackfillVersion == TemplateBackfill.version)
    }

    // MARK: - What must not be overwritten

    @Test func aHandEditedTemplateIsNeverRewrittenFromHistory() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 1)
        seedYesterdaysHistory(ctx, in: workout)
        // The athlete deliberately set 80 kg in the Workout Editor *today* — newer
        // information than yesterday's session.
        let template = workout.orderedItems[0].orderedSets[0]
        template.weightKg = 80
        template.markEdited()
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
        seedYesterdaysHistory(ctx, in: workout)
        let template = workout.orderedItems[0].orderedSets[0]
        template.weightKg = 70
        template.markEdited()               // a newer session already wrote this
        try ctx.save()

        TemplateBackfill.run(context: ctx)
        #expect(template.weightKg == 70)
    }

    @Test func noHistoryLeavesTheGeneratorsEstimateAlone() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx)

        #expect(TemplateBackfill.run(context: ctx) == 0)
        #expect(workout.orderedItems[0].orderedSets.allSatisfy { $0.weightKg == 50 })

        // Nothing logged, so the plan's own numbers are all there is.
        let session = SessionBuilder.start(workout: workout, into: ctx)
        #expect(session.exercises.first!.orderedSets.allSatisfy { $0.weightKg == 50 })
    }

    @Test func moreTemplatesThanLoggedSetsKeepsTheSurplusAsASeed() throws {
        let ctx = makeContext()
        let workout = seedWorkout(ctx, sets: 4)     // plan prescribes four
        seedYesterdaysHistory(ctx, in: workout)     // only three were logged

        #expect(TemplateBackfill.run(context: ctx) == 3)
        let templates = workout.orderedItems[0].orderedSets
        #expect(templates.map(\.weightKg) == [60, 60, 57.5, 50])
        #expect(templates[3].updatedAt == nil)      // never logged against
    }
}
