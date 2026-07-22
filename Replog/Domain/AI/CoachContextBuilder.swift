//
//  CoachContextBuilder.swift
//  Replog
//
//  Assembles a `CoachContext` from the SwiftData store for the two surfaces the coach appears
//  on — the post-session debrief and the Today "Coach" card — and records surfaced insights
//  into the durable `CoachingLog` memory. The pure reasoning lives in `CoachEngine`; this is
//  the MainActor glue that reads models and writes the memory.
//

import Foundation
import SwiftData

@MainActor
enum CoachContextBuilder {

    // MARK: - Session outcome (capture BEFORE finishing)

    /// Distills a live session into a `SessionOutcome`. Call this *before* `SessionFinisher`
    /// writes history, so each lift's PR is judged against the athlete's prior best.
    static func sessionOutcome(from session: ActiveSession,
                               context: ModelContext,
                               catalog: ExerciseCatalog = .shared) -> SessionOutcome {
        var lifts: [FinishedLift] = []
        var totalVolume = 0.0
        var previousTotal = 0.0
        var hadPrevious = false

        for exercise in session.orderedExercises {
            let done = exercise.sets.filter(\.done)
            guard !done.isEmpty else { continue }
            let top = done.max {
                Formulas.e1rm(kg: $0.weightKg, reps: $0.reps) < Formulas.e1rm(kg: $1.weightKg, reps: $1.reps)
            }!
            let e1rm = Formulas.e1rmRounded(kg: top.weightKg, reps: top.reps)
            let prior = context.history(forExercise: exercise.exId)
            let priorBest = prior.map(\.e1rm).max() ?? 0
            let volume = done.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
            totalVolume += volume
            if let last = prior.max(by: { $0.date < $1.date }) {
                previousTotal += last.sets.reduce(0.0) { $0 + $1.w * Double($1.r) }
                hadPrevious = true
            }
            lifts.append(FinishedLift(
                exId: exercise.exId,
                name: catalog.exercise(id: exercise.exId)?.name ?? ReportComposer.prettyName(exercise.exId),
                topWeightKg: top.weightKg, topReps: top.reps, e1rm: e1rm,
                isPR: e1rm > priorBest && priorBest > 0,   // first-ever session isn't a "PR"
                volumeKg: volume))
        }

        return SessionOutcome(lifts: lifts, totalVolumeKg: totalVolume,
                              previousTotalVolumeKg: hadPrevious ? previousTotal : nil,
                              isFullyComplete: session.isComplete)
    }

    // MARK: - Contexts

    /// The debrief context, built AFTER finishing (so history includes the new session).
    static func debriefContext(outcome: SessionOutcome,
                               profile: UserProfile,
                               settings: AppSettings,
                               programDeloadRule: String?,
                               context: ModelContext,
                               catalog: ExerciseCatalog = .shared,
                               now: Date = Date()) -> CoachContext {
        var histories: [String: [HistoryEntry]] = [:]
        var names: [String: String] = [:]
        for lift in outcome.lifts {
            histories[lift.exId] = context.history(forExercise: lift.exId)
            names[lift.exId] = lift.name
        }
        return CoachContext(
            goal: profile.goal, units: settings.units, now: now,
            justFinished: outcome,
            historyByExercise: histories, exerciseNames: names,
            workoutStreak: profile.workoutStreak, weekStreak: profile.weekStreak,
            programDeloadRule: programDeloadRule,
            isFreshUser: false)
    }

    /// The Today-card context: no finished session, but the athlete's recent lifts, streaks,
    /// bodyweight trend, adherence, and check-in cadence.
    static func todayContext(profile: UserProfile,
                             settings: AppSettings,
                             plans: [Plan],
                             context: ModelContext,
                             catalog: ExerciseCatalog = .shared,
                             now: Date = Date()) -> CoachContext {
        // Recent lifts (last 56 days) grouped by exercise, so stalls surface without a finish.
        let cutoff = now.addingTimeInterval(-56 * 86_400)
        let recent = (try? context.fetch(FetchDescriptor<HistoryEntry>()))?.filter { $0.date >= cutoff } ?? []
        var histories: [String: [HistoryEntry]] = [:]
        var names: [String: String] = [:]
        for entry in recent {
            histories[entry.exId, default: []].append(entry)
            names[entry.exId] = catalog.exercise(id: entry.exId)?.name ?? ReportComposer.prettyName(entry.exId)
        }

        let today = Weekday.from(now)
        let scheduledToday = plans.flatMap(\.workouts).contains { !$0.isExtra && $0.day == today }
        let completedToday = Calendar.current.isDateInToday(profile.doneDates.max() ?? .distantPast)

        let bwEntries = (try? context.fetch(FetchDescriptor<BodyweightEntry>())) ?? []
        let snapshot = BodyweightTracker.snapshot(entries: bwEntries)
        let checkInDue = BodyweightTracker.checkInDue(lastDate: snapshot?.date, now: now)

        let deloadRule = plans.first { !$0.progressionDeload.isEmpty }?.progressionDeload

        // A recurring readiness pattern this week (three-plus low-sleep days, etc.).
        let readiness = context.recentReadiness(days: ReadinessModulator.patternWindowDays, now: now)
        let pattern = ReadinessModulator.recentPattern(
            ratings: readiness.map(\.checkIn), forDates: readiness.map(\.date), now: now)

        return CoachContext(
            goal: profile.goal, units: settings.units, now: now,
            justFinished: nil,
            historyByExercise: histories, exerciseNames: names,
            workoutStreak: profile.workoutStreak, weekStreak: profile.weekStreak,
            hasScheduledWorkoutToday: scheduledToday,
            completedScheduledToday: completedToday,
            bodyweight: snapshot, bodyweightCheckInDue: checkInDue,
            programDeloadRule: deloadRule,
            readinessPattern: pattern,
            isFreshUser: recent.isEmpty && profile.totalWorkouts == 0)
    }

    // MARK: - Recording to the coaching memory

    /// Records the debrief's durable insights (the session summary + any milestones/PRs) to the
    /// coaching memory. Stall alerts are intentionally skipped — `StallDetector` already records
    /// those once per stall during `SessionFinisher.finish`.
    @discardableResult
    static func recordDebrief(_ insights: [CoachInsight],
                              context: ModelContext,
                              now: Date = Date()) -> [CoachingLog] {
        insights
            .filter { $0.kind == .sessionDebrief || $0.kind == .milestone }
            .map { record($0, into: context, date: now) }
    }

    /// Records the Today card's single insight, but at most one coach-card note per day.
    @discardableResult
    static func recordDailyCard(_ insight: CoachInsight,
                               context: ModelContext,
                               now: Date = Date()) -> CoachingLog? {
        // Stall alerts are owned by StallDetector; don't double-record.
        guard insight.kind != .stallAlert else { return nil }
        let alreadyToday = context.coachingLogs(kind: .coachInsight, limit: 1)
            .first.map { Calendar.current.isDate($0.date, inSameDayAs: now) } ?? false
        guard !alreadyToday else { return nil }
        return record(insight, into: context, date: now)
    }

    private static func record(_ insight: CoachInsight, into context: ModelContext, date: Date) -> CoachingLog {
        context.recordCoaching(
            .coachInsight, summary: insight.title, date: date, exId: insight.exId,
            payload: CoachingPayload(metrics: insight.metrics, tags: insight.tags + [insight.kind.rawValue]),
            bodyMarkdown: insight.body)
    }
}
