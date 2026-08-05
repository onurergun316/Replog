//
//  PlanOfferTests.swift
//  ReplogTests
//
//  The four sentences the paywall is legally obliged to get right.
//
//  Apple requires a subscription screen to state the term's length and price, and — where an
//  introductory offer exists — what happens when it ends. These properties are that
//  disclosure, so they are asserted rather than eyeballed.
//
//  The one that genuinely costs money if it is wrong is `callToAction`: "Try For Free" above a
//  plan with no trial charges somebody who was told it would not.
//

import Testing
import Foundation
@testable import Replog

struct PlanOfferTests {

    private let yearly = PlanOffer(term: .yearly, displayPrice: "$29.99",
                                   perMonthPrice: "$2.50", freeTrialText: "3 days",
                                   savingsPercent: 50)
    private let monthly = PlanOffer(term: .monthly, displayPrice: "$4.99")

    // MARK: - The price line

    @Test func aYearlyPriceIsShownPerMonthAndPerYear() {
        #expect(yearly.priceLine == "$2.50 per month ($29.99 per year)")
    }

    @Test func aMonthlyPriceIsShownOnce() {
        #expect(monthly.priceLine == "$4.99 per month")
    }

    /// Without a per-month figure there is nothing to divide, so it states the plain price
    /// rather than an empty bracket.
    @Test func aYearlyPriceWithoutAMonthlyBreakdownFallsBackCleanly() {
        let offer = PlanOffer(term: .yearly, displayPrice: "$29.99")
        #expect(offer.priceLine == "$29.99 per year")
    }

    // MARK: - The badge

    @Test func theSavingsBadgeReadsAsAPercentage() {
        #expect(yearly.savingsBadge == "SAVE 50%")
    }

    @Test func noSavingMeansNoBadgeAtAll() {
        #expect(monthly.savingsBadge == nil)
    }

    // MARK: - The button and the charge

    @Test func aTrialIsOfferedRatherThanSold() {
        #expect(yearly.hasFreeTrial)
        #expect(yearly.callToAction == "Try For Free")
    }

    @Test func aPlanWithoutATrialAsksForTheSale() {
        #expect(!monthly.hasFreeTrial)
        #expect(monthly.callToAction == "Subscribe Now")
    }

    @Test func aTrialStatesWhatHappensWhenItEnds() {
        #expect(yearly.chargeDisclosure == "3 days free, then $29.99 per year.")
    }

    @Test func aPlanWithoutATrialStatesTheChargeAndTheWayOut() {
        #expect(monthly.chargeDisclosure == "$4.99 per month. Cancel any time.")
    }

    /// The offer's copy follows the product, not our intentions. If the store were configured
    /// without the trial, the yearly row must stop promising one.
    @Test func removingTheTrialFromTheProductRemovesItFromTheCopy() {
        let noTrial = PlanOffer(term: .yearly, displayPrice: "$29.99",
                                perMonthPrice: "$2.50", savingsPercent: 50)
        #expect(!noTrial.hasFreeTrial)
        #expect(noTrial.callToAction == "Subscribe Now")
        #expect(!noTrial.chargeDisclosure.contains("free"))
    }
}
