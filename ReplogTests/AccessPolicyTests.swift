//
//  AccessPolicyTests.swift
//  ReplogTests
//
//  The gate decision: who may write, and when the one free day ends.
//
//  Every test pins a UTC calendar and a fixed instant. A policy about calendar days that was
//  only ever tested in the machine's own timezone would pass in London and hand somebody in
//  Auckland either two free days or none.
//

import Testing
import Foundation
@testable import Replog

struct AccessPolicyTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-08-05 at `hour`:`minute` UTC.
    private func august5(hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: hour, minute: minute))!
    }

    private func day(_ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: d))!
    }

    // MARK: - Stamping the free day

    @Test func aMorningLaunchGetsThatSameDay() {
        let stamped = AccessPolicy.freeDay(forFirstLaunchAt: august5(hour: 9), calendar: utc)
        #expect(stamped == day(5))
    }

    @Test func aLaunchJustBeforeTheEveningCutoffStillGetsThatDay() {
        let stamped = AccessPolicy.freeDay(forFirstLaunchAt: august5(hour: 19, minute: 59), calendar: utc)
        #expect(stamped == day(5))
    }

    /// The whole reason the cutoff exists: installing at 23:50 must not buy ten minutes.
    @Test func aLateNightLaunchRollsTheFreeDayToTomorrow() {
        let stamped = AccessPolicy.freeDay(forFirstLaunchAt: august5(hour: 23, minute: 50), calendar: utc)
        #expect(stamped == day(6))
    }

    @Test func theCutoffHourItselfRollsForward() {
        let stamped = AccessPolicy.freeDay(forFirstLaunchAt: august5(hour: 20), calendar: utc)
        #expect(stamped == day(6))
    }

    // MARK: - The gate

    @Test func aSubscriberIsNeverLocked() {
        let access = AccessPolicy.access(isPremium: true, freeDayDate: day(1),
                                         now: day(30), calendar: utc)
        #expect(access == .premium)
    }

    @Test func subscribingOutranksAFreeDayThatHasNotStarted() {
        let access = AccessPolicy.access(isPremium: true, freeDayDate: nil,
                                         now: day(5), calendar: utc)
        #expect(access == .premium)
    }

    /// Before the very first launch finishes stamping. Unlocked rather than locked — meeting a
    /// paywall before the app has drawn a screen would be absurd.
    @Test func anUnstampedFreeDayIsTreatedAsOpen() {
        let access = AccessPolicy.access(isPremium: false, freeDayDate: nil,
                                         now: day(5), calendar: utc)
        #expect(access == .freeDay)
    }

    @Test func theFreeDayIsOpenAllDay() {
        let early = AccessPolicy.access(isPremium: false, freeDayDate: day(5),
                                        now: august5(hour: 0, minute: 1), calendar: utc)
        let late = AccessPolicy.access(isPremium: false, freeDayDate: day(5),
                                       now: august5(hour: 23, minute: 59), calendar: utc)
        #expect(early == .freeDay)
        #expect(late == .freeDay)
    }

    @Test func theDayAfterTheFreeDayIsLocked() {
        let access = AccessPolicy.access(isPremium: false, freeDayDate: day(5),
                                         now: day(6), calendar: utc)
        #expect(access == .locked)
    }

    /// The other half of the late-launch fix. Their free day was rolled to tomorrow, so
    /// tonight — the evening they actually downloaded the app in — has to stay open too.
    @Test func theEveningThatEarnedARolledFreeDayIsStillOpen() {
        let stamped = AccessPolicy.freeDay(forFirstLaunchAt: august5(hour: 23, minute: 50), calendar: utc)
        let access = AccessPolicy.access(isPremium: false, freeDayDate: stamped,
                                         now: august5(hour: 23, minute: 55), calendar: utc)
        #expect(access == .freeDay)
    }

    @Test func aLongLapseStaysLocked() {
        let access = AccessPolicy.access(isPremium: false, freeDayDate: day(1),
                                         now: day(31), calendar: utc)
        #expect(access == .locked)
    }

    // MARK: - The paused session

    @Test func aSessionStartedOnTheFreeDayCanBeFinishedLater() {
        let allowed = AccessPolicy.allowsFinishing(sessionStartedAt: august5(hour: 22),
                                                   isPremium: false, freeDayDate: day(5),
                                                   calendar: utc)
        #expect(allowed)
    }

    @Test func aSessionStartedAfterTheFreeDayCannotBeFinished() {
        let allowed = AccessPolicy.allowsFinishing(sessionStartedAt: day(9),
                                                   isPremium: false, freeDayDate: day(5),
                                                   calendar: utc)
        #expect(!allowed)
    }

    @Test func aSubscriberCanFinishAnySession() {
        let allowed = AccessPolicy.allowsFinishing(sessionStartedAt: day(99),
                                                   isPremium: true, freeDayDate: day(5),
                                                   calendar: utc)
        #expect(allowed)
    }

    // MARK: - Access itself

    @Test func onlyLockedForbidsWriting() {
        #expect(Access.premium.isUnlocked)
        #expect(Access.freeDay.isUnlocked)
        #expect(!Access.locked.isUnlocked)
    }
}
