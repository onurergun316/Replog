//
//  SessionFinisher.swift
//  Replog
//
//  Finishing a workout: write each exercise's top set to History, bump the streak,
//  mark today complete on the calendar, then remove the live session.
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
    /// schedule-aware streak can break. Always recomputes both streaks, then deletes the session.
    @discardableResult
    static func finish(_ session: ActiveSession, profile: UserProfile,
                       context: ModelContext, date: Date = Date()) -> Summary {
        let isComplete = session.isComplete

        var logged = 0
        for exercise in session.exercises {
            let doneSets = exercise.sets.filter(\.done)
            guard !doneSets.isEmpty else { continue }
            let top = doneSets.max {
                Formulas.e1rm(kg: $0.weightKg, reps: $0.reps) < Formulas.e1rm(kg: $1.weightKg, reps: $1.reps)
            }!
            let entry = HistoryEntry(
                exId: exercise.exId,
                date: date,
                topW: top.weightKg,
                topR: top.reps,
                e1rm: Formulas.e1rmRounded(kg: top.weightKg, reps: top.reps),
                sets: doneSets.sorted { $0.order < $1.order }.map { RecordedSet(w: $0.weightKg, r: $0.reps) }
            )
            context.insert(entry)
            logged += 1
        }

        if isComplete {
            profile.totalWorkouts += 1
            profile.doneDates = StreakCalendar.recordingCompletion(date, into: profile.doneDates)
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
