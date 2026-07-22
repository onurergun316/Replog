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

    /// REPLOG_BODYWEIGHT=1 -> Today opens with the bodyweight check-in sheet presented
    /// (no UI automation available, so the entry sheet is verified via launch state).
    static var wantsBodyweightSheet: Bool {
        ProcessInfo.processInfo.environment["REPLOG_BODYWEIGHT"] == "1"
    }

    static var initialTab: MainTabView.Tab? {
        switch ProcessInfo.processInfo.environment["REPLOG_TAB"] {
        case "plans": return .plans
        case "library": return .library
        case "calendar": return .progress // the calendar lives inside the Progress tab
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

        // REPLOG_MINIMAL=1 -> skip the demo plan + lift history (short Today page, so
        // below-the-fold cards like the bodyweight check-in land in a screenshot).
        let minimal = ProcessInfo.processInfo.environment["REPLOG_MINIMAL"] == "1"
        var plan: Plan?
        if !minimal {
            var answers = QuizAnswers()
            answers.firstName = "Alex"
            answers.daysPerWeek = 3
            let generated = PlanGenerator().generate(answers)
            let report = ReportComposer.fallbackMarkdown(answers: answers, plan: generated)
            plan = PlanFactory.insert(generated, into: context, order: 0, reportMarkdown: report)
        }

        // Fabricate a few weeks of history for the first exercise to populate Progress.
        if let firstItem = plan?.orderedWorkouts.first?.orderedItems.first {
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

        // A month of weekly bodyweight check-ins (gently trending down), the last one
        // 8 days ago so the Today card also shows the "Check in due" state.
        let bodyweights: [Double] = [78.6, 78.1, 77.7, 77.4, 76.8]
        for (i, kg) in bodyweights.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(36 - i * 7), to: Date()) ?? Date()
            context.logBodyweight(kg, date: date)
        }

        profile.name = "Alex"
        profile.streak = 3
        profile.weekStreak = 2
        profile.totalWorkouts = 12
        profile.doneDates = StreakCalendar.recordingCompletion(Date(), into: [])
        profile.onboardingDone = true
        try? context.save()

        if !minimal { seedCoachAndReports(context, profile: profile, plan: plan) }

        // Optionally drop straight into a live workout for verification.
        seedActiveIfRequested(context, plan: plan)
    }

    /// Seeds enough state for the OWNER to see the coach features working: a stalling lift
    /// (→ stall insight), completed days in the last week/month (→ a due weekly & monthly
    /// report), a recurring low-sleep readiness pattern, and a recorded Today coach card.
    private static func seedCoachAndReports(_ context: ModelContext, profile: UserProfile, plan: Plan?) {
        let cal = Calendar.current
        let stallEx = plan?.orderedWorkouts.dropFirst().first?.orderedItems.first?.exId
            ?? "Barbell_Bench_Press_-_Medium_Grip"

        // Four flat sessions → a genuine plateau the coach will flag.
        for weeksAgo in [4, 3, 2, 1] {
            let date = cal.date(byAdding: .day, value: -(weeksAgo * 7 - 1), to: Date()) ?? Date()
            context.insert(HistoryEntry(exId: stallEx, date: date, topW: 80, topR: 5, e1rm: 93,
                                        sets: [RecordedSet(w: 80, r: 5), RecordedSet(w: 80, r: 5)]))
        }

        // Completed days across the last completed week/month so reports have a story.
        var dones = profile.doneDates
        for offset in [5, 7, 9, 12, 19, 26] {
            if let d = cal.date(byAdding: .day, value: -offset, to: Date()) { dones.append(d) }
        }
        profile.doneDates = dones

        // Three low-sleep days this week → a readiness-pattern insight.
        for offset in [1, 2, 3] {
            if let d = cal.date(byAdding: .day, value: -offset, to: Date()) {
                context.logReadiness(ReadinessCheckIn(sleep: .poor, soreness: .good, stress: .good), date: d)
            }
        }
        try? context.save()

        // Publish any due weekly & monthly report, and record the top Today insight so the
        // Profile "Coach Insights" + "Training Reports" sections are populated.
        ReportScheduler.runOnActivation(context: context)
        let ctx = CoachContextBuilder.todayContext(
            profile: profile, settings: context.appSettings(), plans: context.allPlans(), context: context)
        if let top = CoachEngine.topInsight(ctx) {
            CoachContextBuilder.recordDailyCard(top, context: context)
        }
        try? context.save()
    }

    private static func seedActiveIfRequested(_ context: ModelContext, plan: Plan?) {
        if ProcessInfo.processInfo.environment["REPLOG_ACTIVE"] == "1",
           let workout = plan?.orderedWorkouts.first {
            let session = SessionBuilder.start(workout: workout, into: context)
            if ProcessInfo.processInfo.environment["REPLOG_COMPLETE"] == "1" {
                // Mark everything done to preview the completion celebration.
                session.exercises.forEach { $0.sets.forEach { $0.done = true } }
            } else if let firstSet = session.orderedExercises.first?.orderedSets.first {
                // Mark the first exercise's first set done so the "crossing" state is visible.
                firstSet.done = true
            }
            try? context.save()
        }
    }
}
#endif
