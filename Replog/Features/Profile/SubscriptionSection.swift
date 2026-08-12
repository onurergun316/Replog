//
//  SubscriptionSection.swift
//  Replog
//
//  Where the athlete finds out what they are paying for, and how to stop.
//
//  Everything Apple asks a subscription app to make reachable is here: what plan is active,
//  when it renews, what it will become if it is changing, and a route to cancelling or
//  switching. Every sentence comes from the pure `SubscriptionSummary`, so this file lays out
//  strings and does not decide them.
//
//  **Cancelling is Apple's screen, not ours.** `.manageSubscriptionsSheet` is the only
//  supported way, and we could not build a real cancel button if we wanted to. What we can do
//  is stop making people hunt through Settings for it, which is the actual complaint behind
//  most "I couldn't cancel" reviews.
//
//  The refresh on that sheet's dismissal is load-bearing. Cancelling or switching there
//  changes renewal info WITHOUT creating a transaction, so `Transaction.updates` never fires —
//  without this the screen would keep showing "Renews on…" to somebody who just cancelled.
//

import SwiftUI
import StoreKit

struct SubscriptionSection: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(PremiumGate.self) private var gate

    @State private var showingManageSheet = false

    private var summary: SubscriptionSummary {
        SubscriptionSummary.make(state: store.state,
                                 access: gate.access,
                                 freeDayDate: gate.freeDayDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Subscription")

            VStack(spacing: 0) {
                statusRow
                if summary.isPremium {
                    Divider().padding(.leading, 14)
                    manageRow
                }
                Divider().padding(.leading, 14)
                restoreRow
            }
            .cardSurface()

            if !summary.isPremium { upgradeButton }
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSheet)
        .onChange(of: showingManageSheet) { _, isShowing in
            // See the file note: a cancellation made in there produces no transaction.
            guard !isShowing else { return }
            Task { await store.refresh(); gate.isPremium = store.isPremium }
        }
        .task { await store.refresh() }
    }

    // MARK: - Rows

    private var statusRow: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemName: summary.isPremium ? "checkmark.seal.fill" : "lock.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.headline)
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                Text(summary.detail)
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var manageRow: some View {
        Button { showingManageSheet = true } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "gearshape.fill")
                VStack(alignment: .leading, spacing: 2) {
                    // The label names reactivation when that is what the athlete came for.
                    Text(summary.canReactivate ? "Reactivate or change plan" : "Manage subscription")
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                    Text("Cancel or switch plan in the App Store")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text3)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    private var restoreRow: some View {
        Button { Task { await store.restore(); gate.isPremium = store.isPremium } } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: "arrow.clockwise")
                Text("Restore purchases")
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                if let error = store.lastError {
                    Text(error)
                        .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    private var upgradeButton: some View {
        PrimaryButton(title: "Get Grewyn Premium", systemImage: "flame.fill") {
            gate.presentPaywall()
        }
    }
}
