//
//  SubscriptionSummary.swift
//  Replog
//
//  What Profile says about your subscription, decided in one pure place.
//
//  Subscription state has more shapes than it looks: renewing, cancelled but still running,
//  in a free trial, in a free trial you already cancelled, switching to the other plan at the
//  next renewal, and failing to bill. Each needs a different sentence and a different date, and
//  getting one wrong means telling somebody they are covered when they are not.
//
//  So none of that phrasing lives in the view. `SubscriptionSummary.make` maps a distilled
//  `SubscriptionState` to the exact two lines shown, every branch is enumerated here, and the
//  tests walk all of them. The view only lays out the result.
//
//  One rule worth stating: a **downgrade defers, an upgrade is immediate**. StoreKit applies
//  monthly→yearly at once (with proration it calculates — we must never compute proration
//  ourselves), while yearly→monthly waits for the renewal date. So `pendingTerm` in practice
//  only ever describes a downgrade, and the summary names both the plan you are on and the one
//  you are heading to, with the date it changes.
//

import Foundation

/// Everything the app knows about a subscription, distilled from StoreKit into plain values
/// so the display logic is testable without a store.
nonisolated struct SubscriptionState: Equatable, Sendable {
    /// The term currently entitling the athlete, or nil when they are free.
    var activeTerm: PremiumTerm?
    /// The term this becomes at the next renewal, when it differs from `activeTerm`.
    /// Only a downgrade lands here; an upgrade takes effect immediately.
    var pendingTerm: PremiumTerm?
    /// Whether it will renew. False means cancelled — still entitled until `renewalDate`.
    var willAutoRenew: Bool
    /// When the current period ends: the renewal date, the cancellation date, or the moment a
    /// free trial converts to paid. All three are the same instant.
    var renewalDate: Date?
    /// Whether the current period is an introductory free trial.
    var isInTrial: Bool
    /// Whether Apple is retrying a failed payment. Still entitled, but at risk.
    var isInBillingRetry: Bool

    init(activeTerm: PremiumTerm? = nil, pendingTerm: PremiumTerm? = nil,
         willAutoRenew: Bool = true, renewalDate: Date? = nil,
         isInTrial: Bool = false, isInBillingRetry: Bool = false) {
        self.activeTerm = activeTerm
        self.pendingTerm = pendingTerm
        self.willAutoRenew = willAutoRenew
        self.renewalDate = renewalDate
        self.isInTrial = isInTrial
        self.isInBillingRetry = isInBillingRetry
    }

    /// No subscription.
    static let free = SubscriptionState()

    var isPremium: Bool { activeTerm != nil }
}

/// The two lines Profile renders, plus whether to offer reactivation.
nonisolated struct SubscriptionSummary: Equatable, Sendable {
    /// The bold line: "Replog Premium" or "Free".
    var headline: String
    /// The explanatory line underneath. Never empty, and never ends in a dangling "on".
    var detail: String
    /// Whether to show a Reactivate affordance — true only while cancelled and still running.
    var canReactivate: Bool
    var isPremium: Bool
}

extension SubscriptionSummary {

    static let premiumHeadline = "Grewyn Premium"
    static let freeHeadline = "Free"

    /// The summary for a given state. `access` and `freeDayDate` are only consulted when the
    /// athlete has no subscription, to say something true about the free day rather than a
    /// generic "not subscribed".
    static func make(state: SubscriptionState,
                     access: Access = .locked,
                     freeDayDate: Date? = nil,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> SubscriptionSummary {
        guard let active = state.activeTerm else {
            return free(access: access, freeDayDate: freeDayDate, now: now, calendar: calendar)
        }

        let plan = active.displayName
        let when = state.renewalDate.map(dateText)

        // Billing trouble outranks everything: they are still entitled, but about to stop
        // being, and the fix is theirs to make.
        if state.isInBillingRetry {
            return SubscriptionSummary(
                headline: premiumHeadline,
                detail: "\(plan) · Payment issue — update your payment method",
                canReactivate: false, isPremium: true)
        }

        // Cancelled, still running. Say when it stops, and offer the way back.
        if !state.willAutoRenew {
            let tail: String
            switch (state.isInTrial, when) {
            case (true, let date?):  tail = "Free trial ends \(date) — you won't be charged"
            case (true, nil):        tail = "Free trial ending — you won't be charged"
            case (false, let date?): tail = "Ends \(date)"
            case (false, nil):       tail = "Cancelled — access continues until the period ends"
            }
            return SubscriptionSummary(headline: premiumHeadline, detail: "\(plan) · \(tail)",
                                       canReactivate: true, isPremium: true)
        }

        // Switching plans at the next renewal. Name both, and the date it happens — the whole
        // question somebody opens this screen to answer.
        if let pending = state.pendingTerm, pending != active {
            let tail = when.map { "Switches to \(pending.displayName) on \($0)" }
                ?? "Switches to \(pending.displayName) at the next renewal"
            return SubscriptionSummary(headline: premiumHeadline, detail: "\(plan) · \(tail)",
                                       canReactivate: false, isPremium: true)
        }

        // In a trial that will convert.
        if state.isInTrial {
            let tail = when.map { "Free trial ends \($0)" } ?? "Free trial active"
            return SubscriptionSummary(headline: premiumHeadline, detail: "\(plan) · \(tail)",
                                       canReactivate: false, isPremium: true)
        }

        let tail = when.map { "Renews on \($0)" } ?? "Active"
        return SubscriptionSummary(headline: premiumHeadline, detail: "\(plan) · \(tail)",
                                   canReactivate: false, isPremium: true)
    }

    // MARK: - Free

    private static func free(access: Access, freeDayDate: Date?,
                             now: Date, calendar: Calendar) -> SubscriptionSummary {
        let detail: String
        switch access {
        case .premium, .freeDay:
            detail = "Full access today — subscribe to keep training tomorrow"
        case .locked:
            detail = freeDayDate.map { "Your free day was \(dateText($0))" }
                ?? "Read-only — subscribe to log your training"
        }
        return SubscriptionSummary(headline: freeHeadline, detail: detail,
                                   canReactivate: false, isPremium: false)
    }

    // MARK: - Formatting

    /// "14 Sep 2026" — matching how dates read everywhere else in the app.
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
