//
//  BadgeAwardingTests.swift
//  ReplogTests
//
//  Turning a real store into a snapshot, and a snapshot into awards. The properties that
//  matter: never award the same badge twice, recognise history that already happened, and
//  never invent a personal best out of a movement's first appearance.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct BadgeAwardingTests {

    private func makeContext() -> ModelContext {
        ModelContext(ReplogSchema.inMemoryContainer())
    }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var now: Date {
        DateComponents(calendar: cal, year: 2026, month: 6, day: 30, hour: 12).date!
    }

    private func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

    /// One finished session's worth of history: a single exercise at `kg` for `reps`.
    @discardableResult
    private func logSession(_ ctx: ModelContext, exId: String = "Bench", kg: Double,
                            reps: Int, on date: Date) -> HistoryEntry {
        let entry = HistoryEntry(exId: exId, date: date, topW: kg, topR: reps,
                                 e1rm: Formulas.e1rmRounded(kg: kg, reps: reps),
                                 sets: [RecordedSet(w: kg, r: reps)],
                                 sessionId: UUID())
        ctx.insert(entry)
        let profile = ctx.userProfile()
        profile.totalWorkouts += 1
        profile.doneDates = StreakCalendar.recordingCompletion(date, into: profile.doneDates,
                                                               calendar: cal)
        try? ctx.save()
        return entry
    }

    // MARK: - Awarding

    @Test func theFirstFinishedWorkoutEarnsTheFirstBadge() throws {
        let ctx = makeContext()
        logSession(ctx, kg: 60, reps: 8, on: daysAgo(1))

        let earned = BadgeAwarding.award(context: ctx, now: now, calendar: cal)
        try ctx.save()

        #expect(earned.contains { $0.id == "dayOne" })
        #expect(ctx.earnedBadgeIds().contains("dayOne"))
    }

    @Test func awardingTwiceNeverDuplicates() throws {
        let ctx = makeContext()
        logSession(ctx, kg: 60, reps: 8, on: daysAgo(1))

        BadgeAwarding.award(context: ctx, now: now, calendar: cal)
        try ctx.save()
        let secondPass = BadgeAwarding.award(context: ctx, now: now, calendar: cal)
        try ctx.save()

        // This runs at launch AND after every session, so idempotence is not optional.
        #expect(secondPass.isEmpty)
        let ids = ctx.badgeAwards().map(\.badgeId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func anAwardRemembersWhatWasBeingTrained() throws {
        let ctx = makeContext()
        logSession(ctx, kg: 60, reps: 8, on: daysAgo(1))

        BadgeAwarding.award(context: ctx, planName: "PPL", workoutName: "Push Day",
                            now: now, calendar: cal)
        try ctx.save()

        let award = try #require(ctx.badgeAwards().first { $0.badgeId == "dayOne" })
        #expect(award.planName == "PPL")
        #expect(award.workoutName == "Push Day")
        #expect(award.badge?.name == "Day One")
    }

    @Test func historyThatAlreadyHappenedIsRecognised() throws {
        let ctx = makeContext()
        // An athlete arriving with a year of training behind them.
        for index in 0..<30 {
            logSession(ctx, kg: 60 + Double(index), reps: 5, on: daysAgo(200 - index * 3))
        }

        let earned = BadgeAwarding.award(context: ctx, now: now, calendar: cal)
        try ctx.save()

        // Their board must not open empty, implying none of that counted.
        #expect(earned.contains { $0.id == "dayOne" })
        #expect(earned.contains { $0.id == "twentyFiveLogged" })
        #expect(earned.contains { $0.id == "firstBest" })
    }

    // MARK: - The snapshot

    @Test func aMovementsFirstAppearanceIsNotAPersonalBest() throws {
        let ctx = makeContext()
        logSession(ctx, exId: "Bench", kg: 60, reps: 8, on: daysAgo(10))
        logSession(ctx, exId: "Squat", kg: 100, reps: 5, on: daysAgo(9))

        let snapshot = BadgeAwarding.snapshot(context: ctx, now: now, calendar: cal)

        // Two new lifts, nothing beaten. Counting these would hand out a "personal best"
        // for every movement ever tried.
        #expect(snapshot.personalBestTotal == 0)
    }

    @Test func beatingYourOwnNumberIsAPersonalBest() throws {
        let ctx = makeContext()
        logSession(ctx, kg: 60, reps: 8, on: daysAgo(10))
        logSession(ctx, kg: 65, reps: 8, on: daysAgo(3))

        let snapshot = BadgeAwarding.snapshot(context: ctx, now: now, calendar: cal)
        #expect(snapshot.personalBestTotal == 1)
    }

    @Test func aWeakerSessionIsNotAPersonalBest() throws {
        let ctx = makeContext()
        logSession(ctx, kg: 80, reps: 5, on: daysAgo(10))
        logSession(ctx, kg: 60, reps: 5, on: daysAgo(3))

        let snapshot = BadgeAwarding.snapshot(context: ctx, now: now, calendar: cal)
        #expect(snapshot.personalBestTotal == 0)
    }

    @Test func theSnapshotCountsSessionsNotEntries() throws {
        let ctx = makeContext()
        // One session, three exercises: one workout, not three.
        let sessionId = UUID()
        for exId in ["Bench", "Row", "Squat"] {
            let entry = HistoryEntry(exId: exId, date: daysAgo(2), topW: 60, topR: 8, e1rm: 76,
                                     sets: [RecordedSet(w: 60, r: 8), RecordedSet(w: 60, r: 8)],
                                     sessionId: sessionId)
            ctx.insert(entry)
        }
        try ctx.save()

        let snapshot = BadgeAwarding.snapshot(context: ctx, now: now, calendar: cal)
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.setCount == 6)
        #expect(snapshot.sessions.first?.repCount == 48)
    }

    @Test func perfectWeeksNeedASchedule() throws {
        // With no plan there are no scheduled days, so "perfect" has nothing to mean.
        #expect(BadgeAwarding.perfectWeekCount(scheduledDays: [], doneDates: [daysAgo(2)],
                                               now: now, calendar: cal) == 0)
    }

    @Test func aWeekStillInProgressIsNotYetPerfect() throws {
        // Today is Tuesday. Even a flawless Sunday and Monday cannot make this week perfect
        // yet, because the rest of it has not happened.
        let sunday = daysAgo(2)
        let monday = daysAgo(1)
        let count = BadgeAwarding.perfectWeekCount(scheduledDays: [.sun, .mon],
                                                   doneDates: [sunday, monday],
                                                   now: now, calendar: cal)
        #expect(count == 0)
    }

    @Test func aFinishedWeekWithEveryScheduledDayDoneIsPerfect() throws {
        // The week before last, fully trained on its two scheduled days.
        let lastSunday = daysAgo(9)
        let lastMonday = daysAgo(8)
        let count = BadgeAwarding.perfectWeekCount(scheduledDays: [.sun, .mon],
                                                   doneDates: [lastSunday, lastMonday],
                                                   now: now, calendar: cal)
        #expect(count == 1)
    }

    @Test func anEmptyStoreEarnsNothing() throws {
        let ctx = makeContext()
        let earned = BadgeAwarding.award(context: ctx, now: now, calendar: cal)
        #expect(earned.isEmpty)
        #expect(BadgeAwarding.snapshot(context: ctx, now: now, calendar: cal).totalWorkouts == 0)
    }
}
