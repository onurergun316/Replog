//
//  EntitlementReconciler.swift
//  Replog
//
//  The two judgement calls in the purchase flow, extracted so they can be tested without a
//  store: which plan wins, and whether an empty entitlement read is allowed to take Premium
//  away.
//
//  The second one is the whole reason this file exists. StoreKit's entitlement cache lags a
//  purchase that has just completed — most visibly in Sandbox and against a local `.storekit`
//  configuration, but not only there. The purchase triggers a refresh, that refresh reads no
//  entitlements yet, concludes the athlete has lapsed, and writes them back to free. They paid,
//  the sheet said thank you, and the app locked anyway.
//
//  The fix is a short window after a *verified* purchase during which an EMPTY read cannot
//  revoke. A read that actually found something stays authoritative, so a refund, a lapse or a
//  downgrade still lands immediately — the window forgives silence, not contradiction.
//
//  No StoreKit import. The clock is injected so the window is testable without sleeping.
//

import Foundation

enum EntitlementReconciler {

    /// How long a verified purchase protects against an empty read.
    ///
    /// Long enough to cover a slow Sandbox round trip, short enough that a genuinely failed
    /// purchase does not leave the app unlocked for a meaningful length of time.
    static let optimisticGrantWindow: TimeInterval = 120

    /// The plan that entitles the athlete when more than one somehow does.
    ///
    /// Both products live in one subscription group, so StoreKit should never report both —
    /// but "should never" is not "cannot", and a crossfade at renewal or an upgrade mid-flight
    /// can briefly show two. Yearly wins: it is the longer commitment, so resolving to it can
    /// never shorten what somebody already paid for.
    static func resolveActive(from entitled: [PremiumTerm]) -> PremiumTerm? {
        if entitled.contains(.yearly) { return .yearly }
        return entitled.contains(.monthly) ? .monthly : nil
    }

    /// A live optimistic grant, given when it was made.
    ///
    /// Returns nil once the window has passed, so a stale grant can never keep the app
    /// unlocked indefinitely.
    static func liveGrant(_ grant: (term: PremiumTerm, at: Date)?,
                          now: Date) -> PremiumTerm? {
        guard let grant, now.timeIntervalSince(grant.at) < optimisticGrantWindow else { return nil }
        return grant.term
    }

    /// The state to publish, given what the entitlement read found and any live grant.
    ///
    /// **Only an empty read is overridden.** A read that found entitlements is the truth, even
    /// when it disagrees with a grant we just made — that is what lets a refund or an immediate
    /// plan change apply at once instead of waiting out the window.
    static func reconciled(read: SubscriptionState,
                           grant: (term: PremiumTerm, at: Date)?,
                           now: Date = Date()) -> SubscriptionState {
        guard read.activeTerm == nil, let term = liveGrant(grant, now: now) else { return read }
        // A just-purchased plan renews by definition; we do not yet know its dates.
        return SubscriptionState(activeTerm: term, willAutoRenew: true)
    }
}
