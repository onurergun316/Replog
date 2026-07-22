//
//  NotificationPlanner.swift
//  Replog
//
//  Decides WHAT local notifications to schedule — a pure function over the athlete's schedule,
//  streak, pending report, and check-in cadence, plus the user's preferences. The thin
//  `NotificationScheduler` turns the plan into `UNUserNotificationCenter` requests.
//
//  Hard rules, enforced here so they're unit-testable:
//   • Every kind is individually toggleable, and the master switch gates them all.
//   • Global cap of at most ONE notification per calendar day (highest priority wins).
//   • Quiet hours (default 21:00–09:00): a notification never fires inside them — it's shifted
//     to the next open time.
//   • Copy is always encouraging, never guilt-based.
//

import Foundation

/// A kind of local notification. Priority breaks the one-per-day tie (higher wins).
enum NotificationKind: String, CaseIterable, Sendable {
    case streakRisk       // evening of a scheduled-but-undone day
    case workoutReminder  // a scheduled training day, at the user's chosen time
    case reportReady      // a new weekly/monthly report is waiting
    case checkInDue       // a bodyweight check-in is due

    /// Higher surfaces first when two land on the same day.
    var priority: Int {
        switch self {
        case .streakRisk:      return 3
        case .workoutReminder: return 2
        case .reportReady:     return 1
        case .checkInDue:      return 0
        }
    }
}

/// The user's notification preferences (mirrors the fields on `AppSettings`).
struct NotificationPreferences: Equatable, Sendable {
    var enabled: Bool
    var workoutReminder: Bool
    var streakRisk: Bool
    var reportReady: Bool
    var checkInDue: Bool
    var reminderHour: Int
    var quietStartHour: Int
    var quietEndHour: Int

    func isOn(_ kind: NotificationKind) -> Bool {
        guard enabled else { return false }
        switch kind {
        case .streakRisk:      return streakRisk
        case .workoutReminder: return workoutReminder
        case .reportReady:     return reportReady
        case .checkInDue:      return checkInDue
        }
    }

    static let allOn = NotificationPreferences(
        enabled: true, workoutReminder: true, streakRisk: true, reportReady: true,
        checkInDue: true, reminderHour: 18, quietStartHour: 21, quietEndHour: 9)
}

/// The world state the planner reasons about.
struct NotificationInputs: Sendable {
    var scheduledDays: Set<Weekday>
    /// A scheduled workout today is still undone (drives the evening streak-risk nudge).
    var scheduledTodayUndone: Bool
    var workoutStreak: Int
    /// A published report is waiting to be read.
    var reportReady: Bool
    /// A bodyweight check-in is due.
    var checkInDue: Bool

    init(scheduledDays: Set<Weekday> = [], scheduledTodayUndone: Bool = false,
         workoutStreak: Int = 0, reportReady: Bool = false, checkInDue: Bool = false) {
        self.scheduledDays = scheduledDays
        self.scheduledTodayUndone = scheduledTodayUndone
        self.workoutStreak = workoutStreak
        self.reportReady = reportReady
        self.checkInDue = checkInDue
    }
}

/// A concrete scheduled notification.
struct PlannedNotification: Equatable, Sendable, Identifiable {
    var kind: NotificationKind
    var fireDate: Date
    var title: String
    var body: String

    /// Stable id per kind + calendar day, so re-planning replaces rather than duplicates.
    var id: String {
        "\(kind.rawValue)-\(Int(fireDate.timeIntervalSinceReferenceDate / 86_400))"
    }
}

enum NotificationPlanner {

    /// How many days ahead workout reminders are planned.
    static let horizonDays = 7

    /// Plans the notifications to schedule now. Guarantees at most one per calendar day and
    /// none inside quiet hours. Returns an empty plan when notifications are disabled.
    static func plan(inputs: NotificationInputs, prefs: NotificationPreferences,
                     now: Date = Date(), calendar: Calendar = .current) -> [PlannedNotification] {
        guard prefs.enabled else { return [] }

        var candidates: [PlannedNotification] = []
        candidates += workoutReminders(inputs, prefs, now: now, calendar: calendar)
        if let streak = streakRisk(inputs, prefs, now: now, calendar: calendar) { candidates.append(streak) }
        if let report = reportReady(prefs, now: now, calendar: calendar), inputs.reportReady { candidates.append(report) }
        if let checkIn = checkInDue(prefs, now: now, calendar: calendar), inputs.checkInDue { candidates.append(checkIn) }

        // Shift out of quiet hours, drop anything now in the past.
        let shifted = candidates
            .map { shiftOutOfQuietHours($0, prefs: prefs, calendar: calendar) }
            .filter { $0.fireDate > now }

        // Enforce one-per-day: keep the highest-priority notification each calendar day.
        var bestByDay: [Int: PlannedNotification] = [:]
        for n in shifted {
            let day = calendar.startOfDay(for: n.fireDate).timeIntervalSinceReferenceDate
            let key = Int(day / 86_400)
            if let existing = bestByDay[key] {
                if n.kind.priority > existing.kind.priority { bestByDay[key] = n }
            } else {
                bestByDay[key] = n
            }
        }
        return bestByDay.values.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Candidates

    private static func workoutReminders(_ inputs: NotificationInputs, _ prefs: NotificationPreferences,
                                         now: Date, calendar: Calendar) -> [PlannedNotification] {
        guard prefs.isOn(.workoutReminder), !inputs.scheduledDays.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var out: [PlannedNotification] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard inputs.scheduledDays.contains(Weekday.from(day, calendar: calendar)) else { continue }
            guard let fire = at(hour: prefs.reminderHour, on: day, calendar: calendar) else { continue }
            out.append(PlannedNotification(
                kind: .workoutReminder, fireDate: fire,
                title: "Time to train 💪",
                body: "Your workout is ready whenever you are today. A little effort now pays off."))
        }
        return out
    }

    private static func streakRisk(_ inputs: NotificationInputs, _ prefs: NotificationPreferences,
                                   now: Date, calendar: Calendar) -> PlannedNotification? {
        guard prefs.isOn(.streakRisk), inputs.scheduledTodayUndone, inputs.workoutStreak > 0 else { return nil }
        // Evening nudge, but before quiet hours begin.
        let hour = max(prefs.quietEndHour, min(20, prefs.quietStartHour - 1))
        guard let fire = at(hour: hour, on: calendar.startOfDay(for: now), calendar: calendar) else { return nil }
        return PlannedNotification(
            kind: .streakRisk, fireDate: fire,
            title: "Keep your streak going",
            body: "A quick session today keeps your \(inputs.workoutStreak)-day streak alive — you've got this.")
    }

    private static func reportReady(_ prefs: NotificationPreferences, now: Date,
                                    calendar: Calendar) -> PlannedNotification? {
        guard prefs.isOn(.reportReady),
              let fire = at(hour: prefs.reminderHour, on: calendar.startOfDay(for: now), calendar: calendar)
        else { return nil }
        return PlannedNotification(
            kind: .reportReady, fireDate: fire,
            title: "Your training report is ready",
            body: "See how your training went — tap to read your coach's recap.")
    }

    private static func checkInDue(_ prefs: NotificationPreferences, now: Date,
                                   calendar: Calendar) -> PlannedNotification? {
        guard prefs.isOn(.checkInDue),
              let fire = at(hour: prefs.reminderHour, on: calendar.startOfDay(for: now), calendar: calendar)
        else { return nil }
        return PlannedNotification(
            kind: .checkInDue, fireDate: fire,
            title: "Time for a quick check-in",
            body: "A 10-second weigh-in keeps your trend line honest. No pressure — just data.")
    }

    // MARK: - Quiet hours

    /// True when `hour` (0–23) falls inside the quiet window. Handles the usual overnight
    /// wrap (start > end, e.g. 21→9) and a same-day window (start < end).
    static func isQuietHour(_ hour: Int, prefs: NotificationPreferences) -> Bool {
        let start = prefs.quietStartHour, end = prefs.quietEndHour
        if start == end { return false }               // no quiet window
        if start > end { return hour >= start || hour < end }   // overnight wrap
        return hour >= start && hour < end             // same-day window
    }

    /// Moves a notification out of quiet hours to the next open time (`quietEndHour`), keeping
    /// it on the same day when it was blocked by the morning edge, or pushing to the next day
    /// when it was blocked by the evening edge.
    static func shiftOutOfQuietHours(_ n: PlannedNotification, prefs: NotificationPreferences,
                                     calendar: Calendar) -> PlannedNotification {
        let hour = calendar.component(.hour, from: n.fireDate)
        guard isQuietHour(hour, prefs: prefs) else { return n }
        let day = calendar.startOfDay(for: n.fireDate)
        // Evening edge (at/after start) → open the following morning; morning edge → today.
        let base = hour >= prefs.quietStartHour
            ? (calendar.date(byAdding: .day, value: 1, to: day) ?? day)
            : day
        guard let shifted = at(hour: prefs.quietEndHour, on: base, calendar: calendar) else { return n }
        var copy = n
        copy.fireDate = shifted
        return copy
    }

    // MARK: - Helpers

    /// A `Date` at `hour:00` on the calendar day of `day`.
    private static func at(hour: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: max(0, min(23, hour)), minute: 0, second: 0,
                      of: day, matchingPolicy: .nextTime)
    }
}
