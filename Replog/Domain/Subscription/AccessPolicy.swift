//
//  AccessPolicy.swift
//  Replog
//
//  Who may write, and when. One pure function, and everything in the app that asks
//  "is this allowed" asks it.
//
//  A free athlete gets one calendar day: the day they first opened the app. They onboard,
//  get a plan, train, log every set, finish, read their debrief — the whole product, not a
//  crippled sample of it. When that day ends the app turns read-only: every screen still
//  opens and still shows their real numbers, but nothing new can be written.
//
//  Reading stays open on purpose. Someone who logged a workout and then cannot see it reads
//  that as their own data being held hostage, which is a one-star review rather than a sale.
//
//  Two rules that look like details and are not:
//
//  • **A late first launch rolls the free day forward.** Opening the app for the first time
//    at 23:50 would otherwise buy ten minutes. `freeDay(forFirstLaunchAt:)` moves the day to
//    tomorrow when the first launch lands in the evening.
//  • **Access is "on or before the free day", not "on it".** That is what gives the late
//    installer the tail of their first evening AND the rolled day — a strictly-equal check
//    would lock them out of the very session they downloaded the app to do.
//

import Foundation

/// What an athlete may currently do.
nonisolated enum Access: Equatable, Sendable {
    /// Subscribed. Everything.
    case premium
    /// Inside the one free day. Also everything — the free day is not a limited mode.
    case freeDay
    /// Read-only. Every screen opens; nothing new may be written.
    case locked

    /// Whether writes are allowed. The only question call sites ask.
    var isUnlocked: Bool { self != .locked }
}

enum AccessPolicy {

    /// A first launch at or after this hour rolls the free day to the next day.
    static let lateLaunchHour = 20

    // MARK: - Stamping the free day

    /// The calendar day a first launch at `date` earns. Normally that day; from
    /// `lateLaunchHour` onward, the next one, so a late-night install still gets a usable day.
    ///
    /// Returns a start-of-day, which is what `AppSettings.freeDayDate` stores.
    static func freeDay(forFirstLaunchAt date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) >= lateLaunchHour else { return startOfDay }
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }

    // MARK: - The gate

    /// What the athlete may do right now.
    ///
    /// `freeDayDate == nil` means the very first launch has not finished stamping it yet;
    /// that is treated as unlocked rather than locked, because the alternative is a brand-new
    /// user meeting a paywall before the app has drawn a single screen.
    static func access(isPremium: Bool,
                       freeDayDate: Date?,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> Access {
        if isPremium { return .premium }
        guard let freeDayDate else { return .freeDay }
        // On or before: a rolled free day still covers the evening that earned it.
        return calendar.startOfDay(for: now) <= calendar.startOfDay(for: freeDayDate)
            ? .freeDay
            : .locked
    }

    // MARK: - The paused session

    /// Whether a session started on `startedAt` may still be logged and finished.
    ///
    /// A workout begun on the free day and paused belongs to the athlete. `SessionFinisher`
    /// stamps its history to `startedAt` regardless, so finishing it the next morning writes
    /// nothing that was not already earned — and a workout you can see but can never close is
    /// worse than the day of slack it costs.
    static func allowsFinishing(sessionStartedAt: Date,
                                isPremium: Bool,
                                freeDayDate: Date?,
                                calendar: Calendar = .current) -> Bool {
        if isPremium { return true }
        guard let freeDayDate else { return true }
        return calendar.startOfDay(for: sessionStartedAt) <= calendar.startOfDay(for: freeDayDate)
    }
}
