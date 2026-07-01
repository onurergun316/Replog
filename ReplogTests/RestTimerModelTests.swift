//
//  RestTimerModelTests.swift
//  ReplogTests
//
//  The between-sets rest countdown: start/renew, adjust, skip, and the derived
//  remaining/fraction used to render the ring.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct RestTimerModelTests {

    @Test func startBeginsRunningCountdown() {
        let t = RestTimerModel()
        #expect(!t.isRunning)
        t.start(seconds: 90)
        #expect(t.isRunning)
        #expect(t.total == 90)
        let end = t.endDate!
        #expect(t.remaining(at: end) == 0)
        #expect(t.remaining(at: end.addingTimeInterval(-30)) == 30)
        #expect(abs(t.fraction(at: end.addingTimeInterval(-45)) - 0.5) < 0.02)
    }

    @Test func startClampsToAtLeastOneSecond() {
        let t = RestTimerModel()
        t.start(seconds: 0)
        #expect(t.total == 1)
    }

    @Test func restartRenewsTheCountdown() {
        let t = RestTimerModel()
        t.start(seconds: 30)
        let firstEnd = t.endDate!
        t.start(seconds: 60)          // renew (e.g. next set completed)
        #expect(t.total == 60)
        #expect(t.endDate! > firstEnd)
    }

    @Test func adjustExtendsAndClampsMinimum() {
        let t = RestTimerModel()
        t.start(seconds: 60)
        t.adjust(30)
        #expect(t.total == 90)
        t.adjust(-1000)               // can't go below 15s total
        #expect(t.total == 15)
    }

    @Test func adjustIsNoOpWhenIdle() {
        let t = RestTimerModel()
        t.adjust(15)
        #expect(!t.isRunning)
    }

    @Test func skipStopsTheTimer() {
        let t = RestTimerModel()
        t.start(seconds: 60)
        t.skip()
        #expect(!t.isRunning)
        #expect(t.remaining(at: Date()) == 0)
    }

    @Test func fractionStaysWithinUnitRange() {
        let t = RestTimerModel()
        t.start(seconds: 60)
        let end = t.endDate!
        #expect(t.fraction(at: end.addingTimeInterval(-120)) == 1)  // clamped high
        #expect(t.fraction(at: end.addingTimeInterval(120)) == 0)   // clamped low
    }
}
