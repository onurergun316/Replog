//
//  SubscriptionSummaryTests.swift
//  ReplogTests
//
//  Every sentence Profile can show about a subscription.
//
//  The point of walking all of them is that a wrong one tells somebody they are covered when
//  they are not, or that they will be charged when they will not. There is also a test that no
//  state — including the ones where StoreKit gave us no date — can produce a dangling
//  "Renews on " with nothing after it.
//

import Testing
import Foundation
@testable import Replog

struct SubscriptionSummaryTests {

    private let renewal = Date(timeIntervalSince1970: 1_789_000_000)   // 8 Sep 2026

    private func summary(_ state: SubscriptionState) -> SubscriptionSummary {
        SubscriptionSummary.make(state: state)
    }

    // MARK: - Free

    @Test func noSubscriptionReadsAsFree() {
        let result = SubscriptionSummary.make(state: .free, access: .locked)
        #expect(result.headline == SubscriptionSummary.freeHeadline)
        #expect(!result.isPremium)
        #expect(!result.canReactivate)
    }

    @Test func aFreeAthleteStillInsideTheirDayIsToldItEndsTomorrow() {
        let result = SubscriptionSummary.make(state: .free, access: .freeDay)
        #expect(result.detail.contains("today"))
        #expect(result.detail.contains("tomorrow"))
    }

    @Test func aLockedAthleteIsToldWhenTheirFreeDayWas() {
        let freeDay = Date(timeIntervalSince1970: 1_754_000_000)
        let result = SubscriptionSummary.make(state: .free, access: .locked, freeDayDate: freeDay)
        #expect(result.detail.contains(SubscriptionSummary.dateText(freeDay)))
    }

    // MARK: - Subscribed

    @Test func anActiveYearlyNamesThePlanAndTheRenewalDate() {
        let result = summary(SubscriptionState(activeTerm: .yearly, renewalDate: renewal))
        #expect(result.headline == SubscriptionSummary.premiumHeadline)
        #expect(result.isPremium)
        #expect(result.detail.contains("Yearly"))
        #expect(result.detail.contains("Renews on"))
        #expect(result.detail.contains(SubscriptionSummary.dateText(renewal)))
        #expect(!result.canReactivate)
    }

    @Test func anActiveMonthlyNamesMonthly() {
        let result = summary(SubscriptionState(activeTerm: .monthly, renewalDate: renewal))
        #expect(result.detail.hasPrefix("Monthly"))
    }

    @Test func aTrialSaysWhenItEndsRatherThanWhenItRenews() {
        let result = summary(SubscriptionState(activeTerm: .yearly, renewalDate: renewal, isInTrial: true))
        #expect(result.detail.contains("Free trial ends"))
        #expect(!result.detail.contains("Renews on"))
    }

    @Test func aCancelledPlanSaysWhenAccessEndsAndOffersReactivation() {
        let result = summary(SubscriptionState(activeTerm: .yearly, willAutoRenew: false,
                                               renewalDate: renewal))
        #expect(result.detail.contains("Ends"))
        #expect(result.canReactivate)
        #expect(result.isPremium)   // still entitled until that date
    }

    /// The reassurance that matters most: they cancelled during the trial and want to know
    /// they will not be billed.
    @Test func aCancelledTrialSaysNoChargeIsComing() {
        let result = summary(SubscriptionState(activeTerm: .yearly, willAutoRenew: false,
                                               renewalDate: renewal, isInTrial: true))
        #expect(result.detail.contains("won't be charged"))
        #expect(result.canReactivate)
    }

    @Test func aBillingProblemOutranksEverythingElse() {
        let result = summary(SubscriptionState(activeTerm: .monthly, willAutoRenew: false,
                                               renewalDate: renewal, isInTrial: true,
                                               isInBillingRetry: true))
        #expect(result.detail.contains("Payment issue"))
        #expect(!result.detail.contains("Free trial"))
    }

    // MARK: - Switching

    @Test func aPendingSwitchNamesBothPlansAndTheDate() {
        let result = summary(SubscriptionState(activeTerm: .yearly, pendingTerm: .monthly,
                                               renewalDate: renewal))
        #expect(result.detail.hasPrefix("Yearly"))
        #expect(result.detail.contains("Switches to Monthly"))
        #expect(result.detail.contains(SubscriptionSummary.dateText(renewal)))
    }

    /// StoreKit reports `autoRenewPreference` even when nothing is changing; that is not a switch.
    @Test func aPendingTermEqualToTheActiveOneIsNotASwitch() {
        let result = summary(SubscriptionState(activeTerm: .yearly, pendingTerm: .yearly,
                                               renewalDate: renewal))
        #expect(result.detail.contains("Renews on"))
        #expect(!result.detail.contains("Switches"))
    }

    @Test func aCancelledPlanIsNotDescribedAsSwitching() {
        let result = summary(SubscriptionState(activeTerm: .yearly, pendingTerm: .monthly,
                                               willAutoRenew: false, renewalDate: renewal))
        #expect(result.detail.contains("Ends"))
        #expect(!result.detail.contains("Switches"))
    }

    // MARK: - Missing dates

    /// StoreKit does not always hand back a date. No branch may render "Renews on " and stop.
    @Test func noStateEverPrintsADanglingDatePhrase() {
        let states: [SubscriptionState] = [
            .free,
            SubscriptionState(activeTerm: .yearly),
            SubscriptionState(activeTerm: .monthly, isInTrial: true),
            SubscriptionState(activeTerm: .yearly, willAutoRenew: false),
            SubscriptionState(activeTerm: .yearly, willAutoRenew: false, isInTrial: true),
            SubscriptionState(activeTerm: .yearly, pendingTerm: .monthly),
            SubscriptionState(activeTerm: .monthly, isInBillingRetry: true),
        ]
        for state in states {
            let detail = SubscriptionSummary.make(state: state).detail
            #expect(!detail.isEmpty)
            #expect(!detail.hasSuffix("on "))
            #expect(!detail.hasSuffix("ends "))
            #expect(!detail.contains("  "))
        }
    }
}
