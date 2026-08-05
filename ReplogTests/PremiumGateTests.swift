//
//  PremiumGateTests.swift
//  ReplogTests
//
//  What `require` does with the closure it is handed.
//
//  Two behaviours matter and neither is visible from the call site. Subscribing from a Start
//  button has to actually start the workout, or the athlete pays and then has to find the
//  button again. And dismissing the paywall has to drop the closure, or a "Delete plan" they
//  thought better of fires the next time they subscribe from somewhere else entirely.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct PremiumGateTests {

    private func unlockedGate() -> PremiumGate {
        let gate = PremiumGate()
        gate.debugOverride = .premium
        return gate
    }

    private func lockedGate() -> PremiumGate {
        let gate = PremiumGate()
        gate.debugOverride = .locked
        return gate
    }

    // MARK: - Answering

    @Test func aSubscriberIsUnlocked() {
        let gate = PremiumGate()
        gate.isPremium = true
        #expect(gate.isUnlocked)
        #expect(!gate.isLocked)
    }

    @Test func theDebugOverrideWinsOverTheRealInputs() {
        let gate = PremiumGate()
        gate.isPremium = true
        gate.debugOverride = .locked
        #expect(gate.isLocked)
    }

    // MARK: - require

    @Test func anUnlockedRequireRunsStraightAwayAndShowsNothing() {
        let gate = unlockedGate()
        var ran = false
        gate.require { ran = true }
        #expect(ran)
        #expect(!gate.isPaywallPresented)
    }

    @Test func aLockedRequireHoldsTheActionAndOpensThePaywall() {
        let gate = lockedGate()
        var ran = false
        gate.require { ran = true }
        #expect(!ran)
        #expect(gate.isPaywallPresented)
    }

    /// The payoff: subscribing from a Start button starts the workout.
    @Test func subscribingRunsWhateverTheyWereTryingToDo() {
        let gate = lockedGate()
        var ran = false
        gate.require { ran = true }

        gate.debugOverride = .premium
        gate.didSubscribe()

        #expect(ran)
        #expect(!gate.isPaywallPresented)
    }

    /// Dismissing must forget it. Otherwise a destructive action they backed out of fires
    /// later, from an unrelated paywall.
    @Test func dismissingThePaywallDropsTheHeldAction() {
        let gate = lockedGate()
        var ran = false
        gate.require { ran = true }

        gate.isPaywallPresented = false     // swipe-down
        gate.didSubscribe()                 // as if a later purchase completed

        #expect(!ran)
    }

    @Test func openingThePaywallDirectlyHoldsNoAction() {
        let gate = lockedGate()
        var ran = false
        gate.require { ran = true }
        gate.presentPaywall()               // e.g. the Profile upgrade row
        gate.didSubscribe()
        #expect(!ran)
        #expect(gate.isPaywallPresented == false)
    }

    // MARK: - Finishing a paused session

    @Test func aSessionFromTheFreeDayStaysFinishable() {
        let gate = PremiumGate()
        let calendar = Calendar.current
        let freeDay = calendar.startOfDay(for: Date())
        gate.freeDayDate = freeDay
        #expect(gate.allowsFinishing(sessionStartedAt: freeDay.addingTimeInterval(3600)))
    }

    @Test func theDebugOverrideAlsoDecidesFinishing() {
        let gate = lockedGate()
        #expect(!gate.allowsFinishing(sessionStartedAt: Date()))
    }
}

struct ReviewPromptTests {

    @Test func twoDaysIsNotEnough() {
        #expect(!ReviewPrompt.shouldRequest(completedDayCount: 2, alreadyRequested: false))
    }

    @Test func theThirdDayEarnsTheAsk() {
        #expect(ReviewPrompt.shouldRequest(completedDayCount: 3, alreadyRequested: false))
    }

    @Test func aLongtimeAthleteWhoWasNeverAskedIsStillAsked() {
        #expect(ReviewPrompt.shouldRequest(completedDayCount: 400, alreadyRequested: false))
    }

    @Test func nobodyIsEverAskedTwice() {
        #expect(!ReviewPrompt.shouldRequest(completedDayCount: 3, alreadyRequested: true))
        #expect(!ReviewPrompt.shouldRequest(completedDayCount: 400, alreadyRequested: true))
    }

    @Test func aFreshInstallIsNotAsked() {
        #expect(!ReviewPrompt.shouldRequest(completedDayCount: 0, alreadyRequested: false))
    }
}
