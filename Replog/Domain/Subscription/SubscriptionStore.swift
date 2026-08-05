//
//  SubscriptionStore.swift
//  Replog
//
//  The only file in the app that imports StoreKit.
//
//  Everything the rest of Replog needs to know about money arrives through this one object:
//  the two products, whether the athlete is entitled, and the dates Profile prints. The
//  decisions with any judgement in them live next door in `EntitlementReconciler`, which has
//  no StoreKit import and is therefore actually testable.
//
//  Four things here are not stylistic, and each is a real bug if it is dropped:
//
//  1. **`Transaction.currentEntitlements` is the truth.** `Product.SubscriptionInfo.status`
//     is enrichment ONLY — it tells us whether a subscription will renew and what it will
//     renew into. It frequently returns nothing at all, so anything that lets it take
//     entitlement away is a bug that logs paying athletes out.
//  2. **Refreshes are serialised.** Seven or so call sites overlap in practice — launch,
//     foreground, the transaction listener, after a purchase, after a restore, and both
//     Profile sheets. Each suspends at its StoreKit awaits, so left unchained they interleave
//     and whichever finishes LAST wins, which may be the one that read stale entitlements.
//     Chaining makes it last-started-last-applied.
//  3. **A verified purchase opens an optimistic window** (see `EntitlementReconciler`).
//  4. **The `Transaction.updates` listener starts at launch and is never cancelled**, so
//     renewals, refunds, Ask-to-Buy approvals and purchases made on another device land.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionStore {

    // MARK: - Published state

    /// The loaded products, keyed by term. Empty until `loadProducts` succeeds — the paywall
    /// shows a spinner rather than inventing prices.
    private(set) var products: [PremiumTerm: Product] = [:]

    /// Everything Profile and the gate read.
    private(set) var state: SubscriptionState = .free

    /// The term currently being purchased, for the CTA's spinner.
    private(set) var purchasing: PremiumTerm?

    /// A failed purchase or restore, in words. Cleared on the next attempt.
    ///
    /// The rest of the app degrades silently when something optional fails; a purchase is not
    /// optional. Somebody who just tapped a price and saw nothing happen needs to be told why.
    private(set) var lastError: String?

    var isPremium: Bool { state.isPremium }

    func product(for term: PremiumTerm) -> Product? { products[term] }

    // MARK: - Internals

    private let clock: () -> Date
    /// The last verified purchase, protecting against an empty read. See `EntitlementReconciler`.
    private var grant: (term: PremiumTerm, at: Date)?
    private var updatesListener: Task<Void, Never>?
    /// The tail of the refresh chain. Each refresh awaits the previous one.
    private var refreshChain: Task<Void, Never>?

    init(clock: @escaping @Sendable () -> Date = Date.init) {
        self.clock = clock
    }

    /// Starts the transaction listener and does the first read. Call once, at launch.
    ///
    /// The listener is deliberately never cancelled: it must outlive every screen, and this
    /// object lives as long as the app does.
    func start() {
        guard updatesListener == nil else { return }
        updatesListener = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    // MARK: - Products

    /// Fetches both products. Failure leaves `products` empty, which the paywall renders as a
    /// loading state — never as a free-looking screen with no prices.
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: PremiumTerm.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                PremiumTerm.term(forProductID: product.id).map { ($0, product) }
            })
        } catch {
            products = [:]
        }
    }

    // MARK: - Refresh

    /// Re-reads entitlement. Safe to call from anywhere, as often as you like.
    func refresh() async {
        let previous = refreshChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.performRefresh()
        }
        refreshChain = task
        await task.value
    }

    private func performRefresh() async {
        let read = await readEntitlements()
        let enriched = await enrich(read)
        state = EntitlementReconciler.reconciled(read: enriched, grant: grant, now: clock())
    }

    /// What the athlete is actually entitled to, right now. Authoritative.
    private func readEntitlements() async -> SubscriptionState {
        var entitled: [PremiumTerm] = []
        var expiry: [PremiumTerm: Date] = [:]
        var trialing: Set<PremiumTerm> = []
        let now = clock()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  let term = PremiumTerm.term(forProductID: transaction.productID) else { continue }
            // currentEntitlements can briefly include a just-expired transaction.
            if let expires = transaction.expirationDate, expires <= now { continue }
            entitled.append(term)
            expiry[term] = transaction.expirationDate
            if transaction.offer?.type == .introductory { trialing.insert(term) }
        }

        guard let active = EntitlementReconciler.resolveActive(from: entitled) else { return .free }
        return SubscriptionState(activeTerm: active,
                                 willAutoRenew: true,
                                 renewalDate: expiry[active],
                                 isInTrial: trialing.contains(active))
    }

    /// Overlays renewal intent onto an entitled state: will it renew, what will it renew INTO,
    /// and is billing failing.
    ///
    /// Returns `base` untouched when there is no entitlement, when the products have not
    /// loaded, or when the status query returns nothing. **This function can never grant or
    /// revoke entitlement** — that asymmetry is the point of it.
    private func enrich(_ base: SubscriptionState) async -> SubscriptionState {
        guard let active = base.activeTerm,
              let subscription = (products[.yearly] ?? products[.monthly])?.subscription,
              let statuses = try? await subscription.status else { return base }

        var out = base
        for status in statuses {
            // A group reports a status per subscription the athlete has held; only the one
            // backing the current entitlement describes what happens next.
            guard case .verified(let transaction) = status.transaction,
                  PremiumTerm.term(forProductID: transaction.productID) == active,
                  case .verified(let renewal) = status.renewalInfo else { continue }

            out.willAutoRenew = renewal.willAutoRenew
            if let preference = renewal.autoRenewPreference,
               let pending = PremiumTerm.term(forProductID: preference), pending != active {
                out.pendingTerm = pending
            }
            if status.state == .inBillingRetryPeriod { out.isInBillingRetry = true }
        }
        return out
    }

    // MARK: - Buying

    /// Buys `term`. Returns whether the athlete ended up entitled.
    ///
    /// A cancelled or pending purchase returns false without an error: neither is a failure,
    /// and Ask-to-Buy in particular resolves later through `Transaction.updates`.
    @discardableResult
    func purchase(_ term: PremiumTerm) async -> Bool {
        guard let product = products[term] else {
            await loadProducts()
            lastError = products[term] == nil ? "Couldn't reach the App Store. Try again." : nil
            return false
        }

        lastError = nil
        purchasing = term
        defer { purchasing = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // Unverified: do not grant. Re-read and let the truth decide.
                    await refresh()
                    return isPremium
                }
                await transaction.finish()
                grant = (term, clock())
                await refresh()
                return isPremium

            case .userCancelled:
                return false

            case .pending:
                // Awaiting approval (Ask to Buy) or a bank step. Not an error.
                return false

            @unknown default:
                return false
            }
        } catch {
            lastError = "That purchase didn't go through. Please try again."
            return false
        }
    }

    /// Restores purchases made with this Apple Account.
    ///
    /// `AppStore.sync()` prompts for authentication, so it is only ever called from an explicit
    /// "Restore" tap — never automatically at launch.
    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            // A cancelled auth prompt throws too, so this is not necessarily a failure.
        }
        await refresh()
        if !isPremium { lastError = "No active subscription found for this Apple Account." }
    }
}
