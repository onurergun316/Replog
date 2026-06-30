//
//  DebugSeed.swift
//  Replog
//
//  DEBUG-only helpers to launch straight into a populated app for visual checks.
//  Driven by launch environment variables (never used in Release):
//    REPLOG_SEED=1     -> seed a demo plan + history and mark onboarding done
//    REPLOG_TAB=<name> -> initial tab (today|plans|library|progress|profile)
//

import Foundation
import SwiftData

#if DEBUG
@MainActor
enum DebugSeed {
    static var isSeedRequested: Bool {
        ProcessInfo.processInfo.environment["REPLOG_SEED"] == "1"
    }

    static var initialTab: MainTabView.Tab? {
        switch ProcessInfo.processInfo.environment["REPLOG_TAB"] {
        case "plans": return .plans
        case "library": return .library
        case "progress": return .progress
        case "profile": return .profile
        case "today": return .today
        default: return nil
        }
    }

    /// Seeds a demo plan + a little history if the store is empty.
    static func seedIfNeeded(_ context: ModelContext) {
        guard isSeedRequested else { return }
        let profile = context.userProfile()
        if ProcessInfo.processInfo.environment["REPLOG_DARK"] == "1" {
            context.appSettings().darkMode = true
            try? context.save()
        }
        guard !profile.onboardingDone else { return }

        var answers = QuizAnswers()
        answers.daysPerWeek = 3
        let generated = PlanGenerator().generate(answers)
        let plan = PlanFactory.insert(generated, into: context, order: 0)

        // Fabricate a few weeks of history for the first exercise to populate Progress.
        if let firstItem = plan.orderedWorkouts.first?.orderedItems.first {
            let exId = firstItem.exId
            let cal = Calendar.current
            for (i, e1rm) in [92, 96, 99, 104, 110].enumerated() {
                let date = cal.date(byAdding: .day, value: -(28 - i * 7), to: Date()) ?? Date()
                let entry = HistoryEntry(exId: exId, date: date, topW: Double(70 + i * 2), topR: 8,
                                         e1rm: e1rm, sets: [RecordedSet(w: Double(70 + i * 2), r: 8),
                                                            RecordedSet(w: 60, r: 10)])
                context.insert(entry)
            }
        }

        profile.streak = 3
        profile.totalWorkouts = 12
        profile.doneDates = StreakCalendar.recordingCompletion(Date(), into: [])
        profile.onboardingDone = true
        try? context.save()

        // Optionally drop straight into a live workout for verification.
        if ProcessInfo.processInfo.environment["REPLOG_ACTIVE"] == "1",
           let workout = plan.orderedWorkouts.first {
            SessionBuilder.start(workout: workout, into: context)
            try? context.save()
        }
    }
}
#endif
