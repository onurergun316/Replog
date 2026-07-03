//
//  NotificationScheduler.swift
//  Replog
//
//  The thin `UNUserNotificationCenter` boundary: requests permission in context, and turns a
//  `NotificationPlanner` plan into scheduled requests (replacing the previous batch each time).
//  All the *decisions* live in the pure `NotificationPlanner`; this file only talks to the OS.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
enum NotificationScheduler {

    /// Requests notification permission, returning whether it was granted. Call in context
    /// (a Profile toggle or the first Finish) with value copy — never at cold launch.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// The current system authorization status.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Replaces all pending Replog notifications with the given plan. No-op body when the plan
    /// is empty (still clears stale requests).
    static func apply(_ plan: [PlannedNotification]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                        from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

/// Builds the planner's inputs/preferences from the store and (re)schedules. MainActor glue.
@MainActor
enum NotificationCoordinator {

    /// Preferences read from the settings row.
    static func preferences(_ settings: AppSettings) -> NotificationPreferences {
        NotificationPreferences(
            enabled: settings.notificationsEnabled,
            workoutReminder: settings.notifyWorkoutReminder,
            streakRisk: settings.notifyStreakRisk,
            reportReady: settings.notifyReportReady,
            checkInDue: settings.notifyCheckInDue,
            reminderHour: settings.reminderHour,
            quietStartHour: settings.quietStartHour,
            quietEndHour: settings.quietEndHour)
    }

    /// The current world state for the planner.
    static func inputs(context: ModelContext, now: Date = Date()) -> NotificationInputs {
        let plans = context.allPlans()
        let profile = context.userProfile()
        let scheduled = StreakEngine.scheduledDays(in: plans)
        let today = Weekday.from(now)
        let scheduledToday = scheduled.contains(today)
        let doneToday = profile.doneDates.contains { Calendar.current.isDateInToday($0) }

        let reportReady = (context.coachingLogs(kind: .weeklyReport, limit: 1)
            + context.coachingLogs(kind: .monthlyReport, limit: 1))
            .contains { Calendar.current.isDateInToday($0.date) }

        let checkInDue = BodyweightTracker.checkInDue(lastDate: context.latestBodyweight()?.date, now: now)

        return NotificationInputs(
            scheduledDays: scheduled,
            scheduledTodayUndone: scheduledToday && !doneToday,
            workoutStreak: profile.workoutStreak,
            reportReady: reportReady,
            checkInDue: checkInDue)
    }

    /// Re-plans and re-schedules from the current store state. Safe to call on activation and
    /// whenever preferences change. Clears everything when notifications are disabled.
    static func refresh(context: ModelContext, now: Date = Date()) {
        let prefs = preferences(context.appSettings())
        guard prefs.enabled else { NotificationScheduler.cancelAll(); return }
        let plan = NotificationPlanner.plan(inputs: inputs(context: context, now: now), prefs: prefs, now: now)
        NotificationScheduler.apply(plan)
    }
}
