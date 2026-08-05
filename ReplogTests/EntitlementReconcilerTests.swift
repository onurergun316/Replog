//
//  EntitlementReconcilerTests.swift
//  ReplogTests
//
//  The bug this guards against: somebody pays, StoreKit's entitlement cache has not caught up
//  yet, the refresh triggered by their own purchase reads nothing, and the app writes them
//  back to free. The sheet said thank you and the app locked anyway.
//
//  So the asymmetry is the thing under test. An EMPTY read inside the grant window cannot
//  revoke; a read that found something is authoritative even when it disagrees with the grant,
//  which is what lets a refund or an immediate plan change land at once.
//

import Testing
import Foundation
@testable import Replog

struct EntitlementReconcilerTests {

    private let purchasedAt = Date(timeIntervalSince1970: 1_789_000_000)

    private func later(_ seconds: TimeInterval) -> Date {
        purchasedAt.addingTimeInterval(seconds)
    }

    // MARK: - Which plan wins

    @Test func nothingEntitledResolvesToNothing() {
        #expect(EntitlementReconciler.resolveActive(from: []) == nil)
    }

    @Test func aSingleEntitlementWins() {
        #expect(EntitlementReconciler.resolveActive(from: [.monthly]) == .monthly)
        #expect(EntitlementReconciler.resolveActive(from: [.yearly]) == .yearly)
    }

    /// Both can appear briefly at a renewal crossfade. Yearly wins because it is the longer
    /// commitment, so resolving to it can never shorten what was already paid for.
    @Test func yearlyWinsWhenBothAreSomehowEntitled() {
        #expect(EntitlementReconciler.resolveActive(from: [.monthly, .yearly]) == .yearly)
        #expect(EntitlementReconciler.resolveActive(from: [.yearly, .monthly]) == .yearly)
    }

    // MARK: - The grant window

    @Test func aFreshGrantIsLive() {
        let grant = EntitlementReconciler.liveGrant((.yearly, purchasedAt), now: later(1))
        #expect(grant == .yearly)
    }

    @Test func anExpiredGrantIsGone() {
        let window = EntitlementReconciler.optimisticGrantWindow
        let grant = EntitlementReconciler.liveGrant((.yearly, purchasedAt), now: later(window + 1))
        #expect(grant == nil)
    }

    @Test func noGrantIsNeverLive() {
        #expect(EntitlementReconciler.liveGrant(nil, now: purchasedAt) == nil)
    }

    // MARK: - Reconciling

    /// The headline case. This is what stops a paid-for subscription from evaporating.
    @Test func anEmptyReadCannotRevokeInsideTheWindow() {
        let result = EntitlementReconciler.reconciled(read: .free,
                                                      grant: (.yearly, purchasedAt),
                                                      now: later(5))
        #expect(result.activeTerm == .yearly)
        #expect(result.isPremium)
    }

    @Test func anEmptyReadRevokesOnceTheWindowHasPassed() {
        let window = EntitlementReconciler.optimisticGrantWindow
        let result = EntitlementReconciler.reconciled(read: .free,
                                                      grant: (.yearly, purchasedAt),
                                                      now: later(window + 1))
        #expect(result.activeTerm == nil)
    }

    @Test func anEmptyReadWithNoGrantRevokesImmediately() {
        let result = EntitlementReconciler.reconciled(read: .free, grant: nil, now: purchasedAt)
        #expect(result.activeTerm == nil)
    }

    /// A read that found something is the truth. A refund arriving seconds after a purchase
    /// must apply, not wait out the window.
    @Test func aNonEmptyReadOverridesEvenAFreshGrant() {
        let read = SubscriptionState(activeTerm: .monthly, willAutoRenew: false)
        let result = EntitlementReconciler.reconciled(read: read,
                                                      grant: (.yearly, purchasedAt),
                                                      now: later(1))
        #expect(result.activeTerm == .monthly)
        #expect(!result.willAutoRenew)
    }

    @Test func aNonEmptyReadKeepsAllItsDetail() {
        let renews = Date(timeIntervalSince1970: 1_800_000_000)
        let read = SubscriptionState(activeTerm: .yearly, pendingTerm: .monthly,
                                     renewalDate: renews, isInTrial: true)
        let result = EntitlementReconciler.reconciled(read: read, grant: nil, now: purchasedAt)
        #expect(result == read)
    }

    /// A grant describes a purchase that just succeeded, so it renews by definition — the app
    /// must not briefly show it as cancelled while the real dates arrive.
    @Test func aGrantedStateReadsAsRenewing() {
        let result = EntitlementReconciler.reconciled(read: .free,
                                                      grant: (.monthly, purchasedAt),
                                                      now: later(1))
        #expect(result.willAutoRenew)
        #expect(!result.isInBillingRetry)
    }
}
