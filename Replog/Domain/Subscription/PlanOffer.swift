//
//  PlanOffer.swift
//  Replog
//
//  One purchasable plan, already priced, in words the paywall can print.
//
//  Every string here comes from the athlete's own storefront — the currency, the grouping, the
//  trial length — and the paywall never sees a `Product`. That keeps StoreKit contained to one
//  file, and it means the paywall's layout can be built and previewed against made-up offers
//  without a store connection or a signed build.
//
//  Nothing in this type is ever hardcoded at a call site. If the price changes in App Store
//  Connect, this changes, and the screen follows.
//

import Foundation

nonisolated struct PlanOffer: Equatable, Sendable, Identifiable {

    let term: PremiumTerm
    /// The full price for one billing period, formatted: "$29.99".
    let displayPrice: String
    /// A yearly price divided into months, formatted: "$2.50". Nil for the monthly plan.
    let perMonthPrice: String?
    /// The introductory free trial as read from the real product: "3 days". Nil when the
    /// product carries no free trial — which is what makes the copy follow the store rather
    /// than our intentions.
    let freeTrialText: String?
    /// How much cheaper than twelve months, when that is both computable and flattering.
    let savingsPercent: Int?

    var id: PremiumTerm { term }

    var hasFreeTrial: Bool { freeTrialText != nil }

    init(term: PremiumTerm, displayPrice: String, perMonthPrice: String? = nil,
         freeTrialText: String? = nil, savingsPercent: Int? = nil) {
        self.term = term
        self.displayPrice = displayPrice
        self.perMonthPrice = perMonthPrice
        self.freeTrialText = freeTrialText
        self.savingsPercent = savingsPercent
    }

    // MARK: - Copy
    //
    // Apple requires a paywall to state the subscription's length and price, and — where there
    // is an introductory offer — what happens when it ends. These four properties are that
    // disclosure, so the requirement is met in one reviewable place rather than scattered
    // through a view body.

    /// The price line under the plan name.
    /// Yearly: "$2.50 per month ($29.99 per year)". Monthly: "$4.99 per month".
    var priceLine: String {
        guard let perMonthPrice, term == .yearly else {
            return "\(displayPrice) per \(term.periodNoun)"
        }
        return "\(perMonthPrice) per month (\(displayPrice) per year)"
    }

    /// The badge on the row, e.g. "SAVE 50%".
    var savingsBadge: String? {
        savingsPercent.map { "SAVE \($0)%" }
    }

    /// What the button says. A trial is offered, not sold.
    var callToAction: String {
        hasFreeTrial ? "Try For Free" : "Subscribe Now"
    }

    /// The sentence directly beneath the button, stating exactly what will be charged and when.
    /// "3 days free, then $29.99 per year." / "$4.99 per month. Cancel any time."
    var chargeDisclosure: String {
        guard let freeTrialText else {
            return "\(displayPrice) per \(term.periodNoun). Cancel any time."
        }
        return "\(freeTrialText) free, then \(displayPrice) per \(term.periodNoun)."
    }
}
