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
    }

    /// Persists history for every exercise with at least one completed set, updates the
    /// profile (streak, completed day, total workouts), and deletes the session.
    @discardableResult
    static func finish(_ session: ActiveSession, profile: UserProfile,
                       context: ModelContext, date: Date = Date()) -> Summary {
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

        profile.totalWorkouts += 1
        profile.doneDates = StreakCalendar.recordingCompletion(date, into: profile.doneDates)
        profile.streak = StreakCalendar.streak(doneDates: profile.doneDates, today: date)

        let newStreak = profile.streak
        context.delete(session)
        try? context.save()
        return Summary(exercisesLogged: logged, newStreak: newStreak)
    }
}
