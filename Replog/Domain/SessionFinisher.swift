//
//  SessionFinisher.swift
//  Replog
//
//  Finishing a workout: write each exercise's top set to History, record any newly
//  detected stall to the coaching memory, bump the streak, mark today complete on
//  the calendar, then remove the live session.
//

import Foundation
import SwiftData

@MainActor
enum SessionFinisher {

    /// Result of finishing, useful for tests/UI feedback.
    struct Summary: Equatable {
        var exercisesLogged: Int
        var newStreak: Int
        var weekStreak: Int
        /// Whether the workout was fully completed (and therefore counted toward streaks).
        var countedAsComplete: Bool
    }

    /// Persists history for every exercise with at least one completed set. Only a *fully
    /// completed* workout counts toward the streaks and the lifetime total: a partial finish
    /// still saves progress (history) but does not mark the scheduled day done, so the
    /// schedule-aware streak can break. A fully completed workout also writes its logged
    /// weights/reps back onto the plan's templates (`TemplateWriteBack`), so the next
    /// session starts from what was actually lifted. Always recomputes both streaks, then
    /// deletes the session.
    @discardableResult
    static func finish(_ session: ActiveSession, profile: UserProfile,
                       context: ModelContext, date: Date = Date()) -> Summary {
        let isComplete = session.isComplete
        // A workout is logged on the day it STARTED, even when it's finished after midnight —
        // a session begun at 23:00 and finished at 00:15 counts for the 23:00 day. `date`
        // (the finish moment) is kept only for the elapsed duration and the as-of-now streak.
        let loggedDate = session.startedAt
        // Captured before the session is deleted — otherwise this context is lost for good.
        let duration = max(0, Int(date.timeIntervalSince(session.startedAt)))

        var logged = 0
        for exercise in session.exercises {
            let doneSets = exercise.sets.filter(\.done)
            guard !doneSets.isEmpty else { continue }
            // Reps break the tie. Every set of a bodyweight movement scores an estimated
            // 1RM of zero (0 kg x anything), so ranking on that alone picked an arbitrary
            // set — a 5-rep warm-up could be recorded as the top set of a 12-rep session,
            // hiding a real personal record.
            let top = doneSets.max {
                let a = Formulas.e1rm(kg: $0.weightKg, reps: $0.reps)
                let b = Formulas.e1rm(kg: $1.weightKg, reps: $1.reps)
                return a == b ? $0.reps < $1.reps : a < b
            }!
            // Scoped to this session's plan: a stall is a stall *within a program*, and
            // mixing a second plan's loads into the trail invents plateaus and regressions
            // that never happened (see `history(forExercise:inPlan:)`).
            let prior = context.history(forExercise: exercise.exId, inPlan: session.planId)
            let entry = HistoryEntry(
                exId: exercise.exId,
                date: loggedDate,
                topW: top.weightKg,
                topR: top.reps,
                e1rm: Formulas.e1rmRounded(kg: top.weightKg, reps: top.reps),
                sets: doneSets.sorted { $0.order < $1.order }.map { RecordedSet(w: $0.weightKg, r: $0.reps) },
                topRPE: top.rpe,
                sessionId: session.id,
                workoutId: session.workoutId,
                planId: session.planId,
                workoutName: session.name.isEmpty ? nil : session.name,
                planName: session.planName.isEmpty ? nil : session.planName,
                durationSeconds: duration
            )
            context.insert(entry)
            logged += 1

            // The trail just grew — let the long-horizon coach look for a stall and
            // remember its recommendation (deload / swap) once per stall.
            StallDetector.detectAndRecord(
                exId: exercise.exId, history: prior + [entry], context: context, date: date)
        }

        if isComplete {
            // The plan's templates are the athlete's current working numbers, not a frozen
            // prescription: what was just lifted is what the next session starts from.
            TemplateWriteBack.applyIfComplete(session: session, context: context, date: date)
            profile.totalWorkouts += 1
            profile.doneDates = StreakCalendar.recordingCompletion(loggedDate, into: profile.doneDates)
        }
        context.recomputeStreaks(profile: profile, today: date)

        let summary = Summary(
            exercisesLogged: logged,
            newStreak: profile.streak,
            weekStreak: profile.weekStreak,
            countedAsComplete: isComplete
        )
        context.delete(session)
        try? context.save()
        return summary
    }
}
