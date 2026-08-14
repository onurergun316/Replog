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
                                   savingsPercent: 49)
    private let monthly = PlanOffer(term: .monthly, displayPrice: "$4.99")

    // MARK: - The price, and the figure that must stay under it

    /// Guideline 3.1.2(c). Grewyn 1.0 shipped "$2.50 per month ($29.99 per year)" as one string
    /// at one size, leading with the division and bracketing the real charge, and App Review
    /// rejected it. The charge is now a field of its own and the division is a separate,
    /// subordinate one, which is what lets the row rank them.
    @Test func aYearlyPlanLeadsWithTheAmountItCharges() {
        #expect(yearly.price == "$29.99 per year")
        #expect(yearly.perMonthEquivalent == "$2.50 per month")
    }

    @Test func aMonthlyPlanDividesNothing() {
        #expect(monthly.price == "$4.99 per month")
        #expect(monthly.perMonthEquivalent == nil,
                "a plan billed monthly has nothing to spread over months")
    }

    /// Without a per-month figure there is nothing to divide, so it states the plain price
    /// rather than an empty bracket.
    @Test func aYearlyPriceWithoutAMonthlyBreakdownFallsBackCleanly() {
        let offer = PlanOffer(term: .yearly, displayPrice: "$29.99")
        #expect(offer.price == "$29.99 per year")
        #expect(offer.perMonthEquivalent == nil)
    }

    /// The defect Apple named, asserted as a property rather than a string: whatever the
    /// storefront, the charge carries exactly one number and the division is never smuggled
    /// into it. A string assertion passes in dollars and misses the regression in a currency
    /// no test happens to name.
    @Test func theChargeNeverHidesASecondPriceInsideIt() {
        for offer in [yearly, monthly, PlanOffer(term: .yearly, displayPrice: "199,00 kr",
                                                 perMonthPrice: "16,58 kr")] {
            #expect(!offer.price.contains("("), "\(offer.price) hides a second price in brackets")
            #expect(offer.perMonthEquivalent.map { !offer.price.contains($0) } ?? true,
                    "the divided figure must not also appear inside the charge")
        }
    }

    /// VoiceOver has no type scale, so order carries the subordination instead.
    @Test func voiceOverSaysTheChargeBeforeTheDivision() throws {
        let spoken = yearly.spokenPrice
        let charge = try #require(spoken.range(of: "$29.99 per year"))
        let divided = try #require(spoken.range(of: "$2.50 per month"))
        #expect(charge.lowerBound < divided.lowerBound, "the charge is said first")
        #expect(spoken.contains("works out at"), "the division is named as a division")
        #expect(monthly.spokenPrice == "$4.99 per month",
                "nothing to qualify when there is only one price")
    }

    // MARK: - The badge

    @Test func theSavingsBadgeReadsAsAPercentage() {
        #expect(yearly.savingsBadge == "SAVE 49%")
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
                                perMonthPrice: "$2.50", savingsPercent: 49)
        #expect(!noTrial.hasFreeTrial)
        #expect(noTrial.callToAction == "Subscribe Now")
        #expect(!noTrial.chargeDisclosure.contains("free"))
    }
}
