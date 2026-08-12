//
//  PremiumPlanTests.swift
//  ReplogTests
//
//  The product identities, and the arithmetic behind the SAVE badge.
//
//  The identifiers are asserted literally on purpose. They are written into every receipt
//  Apple issues, so changing one silently un-entitles everybody who already paid — a test
//  that fails loudly is the cheapest possible guard against a tidy-up rename.
//

import Testing
import Foundation
@testable import Replog

struct PremiumTermTests {

    @Test func productIdentifiersAreExactlyWhatTheStoreWasConfiguredWith() {
        #expect(PremiumTerm.monthly.productID == "test.Grewyn.premium.monthly")
        #expect(PremiumTerm.yearly.productID == "test.Grewyn.premium.yearly")
    }

    @Test func bothProductsAreRequestedFromTheStore() {
        #expect(Set(PremiumTerm.allProductIDs) == ["test.Grewyn.premium.monthly",
                                                   "test.Grewyn.premium.yearly"])
    }

    /// Yearly first — it carries the trial and it is the better deal, so it leads the paywall.
    @Test func yearlyIsOfferedFirst() {
        #expect(PremiumTerm.allCases.first == .yearly)
    }

    @Test func anIdentifierResolvesBackToItsTerm() {
        #expect(PremiumTerm.term(forProductID: "test.Grewyn.premium.yearly") == .yearly)
        #expect(PremiumTerm.term(forProductID: "test.Grewyn.premium.monthly") == .monthly)
        #expect(PremiumTerm.term(forProductID: "test.Grewyn.pro.lifetime") == nil)
    }

    @Test func onlyYearlyIsMeantToCarryATrial() {
        #expect(PremiumTerm.yearly.intendsFreeTrial)
        #expect(!PremiumTerm.monthly.intendsFreeTrial)
    }

    @Test func eachTermKnowsItsBillingNoun() {
        #expect(PremiumTerm.yearly.periodNoun == "year")
        #expect(PremiumTerm.monthly.periodNoun == "month")
    }
}

struct PremiumPricingTests {

    /// The shipped pair: 12 × 4.99 = 59.88, and 29.99 is 49.9% off, which rounds to 50.
    @Test func theShippedPricesReadAsFiftyPercent() {
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 4.99, yearlyPrice: 29.99) == 50)
    }

    @Test func anExactHalvingIsFiftyPercent() {
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 10, yearlyPrice: 60) == 50)
    }

    /// Never brag about nothing. A yearly plan priced at twelve months has no badge at all
    /// rather than a "SAVE 0%" one.
    @Test func noSavingMeansNoBadge() {
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 5, yearlyPrice: 60) == nil)
    }

    @Test func aYearlyPlanThatCostsMoreHasNoBadge() {
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 5, yearlyPrice: 120) == nil)
    }

    @Test func aMissingPriceHasNoBadge() {
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 0, yearlyPrice: 29.99) == nil)
        #expect(PremiumPricing.savingsPercent(monthlyPrice: 4.99, yearlyPrice: 0) == nil)
    }

    @Test func aYearlyPriceDividesIntoMonthsAtTwoPlaces() {
        #expect(PremiumPricing.monthlyEquivalent(ofYearly: 29.99) == Decimal(string: "2.50"))
        #expect(PremiumPricing.monthlyEquivalent(ofYearly: 60) == Decimal(5))
    }

    @Test func aZeroYearlyPriceDividesToZero() {
        #expect(PremiumPricing.monthlyEquivalent(ofYearly: 0) == 0)
    }
}
