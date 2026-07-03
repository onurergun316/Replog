//
//  NotificationPlannerTests.swift
//  ReplogTests
//
//  The pure notification planner: per-kind toggles + master switch, the one-per-day cap,
//  quiet-hours shifting, and the encouraging-copy contract.
//

import Testing
import Foundation
@testable import Replog

struct NotificationPlannerTests {

    private let cal = Calendar.current

    /// A Monday-morning "now" so scheduled Monday reminders are still in the future.
    private var monday9am: Date {
        // 2026-06-01 is a Monday; 09:00 local.
        cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
    }

    private var everyDay: Set<Weekday> { Set(Weekday.allCases) }

    // MARK: - Master switch & toggles

    @Test func disabledMasterSwitchPlansNothing() {
        var prefs = NotificationPreferences.allOn
        prefs.enabled = false
        let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: true,
                                        workoutStreak: 5, reportReady: true, checkInDue: true)
        #expect(NotificationPlanner.plan(inputs: inputs, prefs: prefs, now: monday9am, calendar: cal).isEmpty)
    }

    @Test func eachKindIsIndividuallyToggleable() {
        // Only workout reminders on; a scheduled week → only workoutReminder kinds appear.
        var prefs = NotificationPreferences.allOn
        prefs.streakRisk = false; prefs.reportReady = false; prefs.checkInDue = false
        let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: true,
                                        workoutStreak: 5, reportReady: true, checkInDue: true)
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: prefs, now: monday9am, calendar: cal)
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { $0.kind == .workoutReminder })
    }

    @Test func workoutReminderRespectsScheduledDaysOnly() {
        var prefs = NotificationPreferences.allOn
        prefs.streakRisk = false; prefs.reportReady = false; prefs.checkInDue = false
        // Only Wednesdays scheduled.
        let inputs = NotificationInputs(scheduledDays: [.wed])
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: prefs, now: monday9am, calendar: cal)
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { cal.component(.weekday, from: $0.fireDate) == Weekday.wed.calendarWeekday })
    }

    // MARK: - One-per-day cap & priority

    @Test func atMostOnePerDayEvenWhenEverythingFires() {
        let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: true,
                                        workoutStreak: 9, reportReady: true, checkInDue: true)
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: .allOn, now: monday9am, calendar: cal)
        let byDay = Dictionary(grouping: plan) { Int(cal.startOfDay(for: $0.fireDate).timeIntervalSinceReferenceDate / 86_400) }
        #expect(byDay.values.allSatisfy { $0.count == 1 })
    }

    @Test func streakRiskOutranksOtherKindsSameDay() throws {
        // Today: workout reminder + streak risk + report + check-in all eligible → streak wins.
        let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: true,
                                        workoutStreak: 9, reportReady: true, checkInDue: true)
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: .allOn, now: monday9am, calendar: cal)
        let today = try #require(plan.first { cal.isDate($0.fireDate, inSameDayAs: monday9am) })
        #expect(today.kind == .streakRisk)
    }

    @Test func propertyNeverMoreThanOnePerDayAcrossManyConfigurations() {
        // Fuzz a range of preference/inputs combos; the cap must always hold.
        for streak in [0, 1, 9] {
            for undone in [true, false] {
                for report in [true, false] {
                    let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: undone,
                                                    workoutStreak: streak, reportReady: report, checkInDue: true)
                    let plan = NotificationPlanner.plan(inputs: inputs, prefs: .allOn, now: monday9am, calendar: cal)
                    let byDay = Dictionary(grouping: plan) {
                        Int(self.cal.startOfDay(for: $0.fireDate).timeIntervalSinceReferenceDate / 86_400)
                    }
                    #expect(byDay.values.allSatisfy { $0.count <= 1 })
                }
            }
        }
    }

    // MARK: - Quiet hours

    @Test func quietHourDetectionHandlesOvernightWrap() {
        let prefs = NotificationPreferences.allOn   // quiet 21–9
        #expect(NotificationPlanner.isQuietHour(22, prefs: prefs))
        #expect(NotificationPlanner.isQuietHour(3, prefs: prefs))
        #expect(NotificationPlanner.isQuietHour(8, prefs: prefs))
        #expect(!NotificationPlanner.isQuietHour(9, prefs: prefs))
        #expect(!NotificationPlanner.isQuietHour(18, prefs: prefs))
    }

    @Test func remindersNeverFireInsideQuietHours() {
        var prefs = NotificationPreferences.allOn
        prefs.reminderHour = 23   // deep inside quiet hours
        let inputs = NotificationInputs(scheduledDays: everyDay)
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: prefs, now: monday9am, calendar: cal)
        #expect(!plan.isEmpty)
        for n in plan {
            let hour = cal.component(.hour, from: n.fireDate)
            #expect(!NotificationPlanner.isQuietHour(hour, prefs: prefs),
                    "\(n.kind) fired at \(hour):00, inside quiet hours")
        }
    }

    @Test func eveningQuietReminderShiftsToNextMorningOpen() {
        var prefs = NotificationPreferences.allOn
        prefs.reminderHour = 23
        let n = PlannedNotification(kind: .workoutReminder,
                                    fireDate: cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23))!,
                                    title: "t", body: "b")
        let shifted = NotificationPlanner.shiftOutOfQuietHours(n, prefs: prefs, calendar: cal)
        #expect(cal.component(.hour, from: shifted.fireDate) == prefs.quietEndHour)   // 09:00
        // Pushed to the next day (June 2), not the same evening.
        #expect(cal.component(.day, from: shifted.fireDate) == 2)
    }

    // MARK: - Copy

    @Test func copyIsEncouragingNotGuiltBased() {
        let inputs = NotificationInputs(scheduledDays: everyDay, scheduledTodayUndone: true,
                                        workoutStreak: 9, reportReady: true, checkInDue: true)
        let plan = NotificationPlanner.plan(inputs: inputs, prefs: .allOn, now: monday9am, calendar: cal)
        let banned = ["missed", "failed", "don't", "lazy", "guilty", "behind", "slacking"]
        for n in plan {
            let text = (n.title + " " + n.body).lowercased()
            for word in banned { #expect(!text.contains(word), "\(n.kind) copy uses guilt word '\(word)'") }
        }
    }
}
