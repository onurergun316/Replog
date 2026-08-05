//
//  PaywallView.swift
//  Replog
//
//  The one screen where Replog asks for money.
//
//  Everything Apple requires of a subscription screen is on it, and stated plainly rather than
//  in a footnote: what you get, the length of each term, the price in your own currency, what
//  happens when the free trial ends, a way to restore a purchase you already made, and the
//  Terms and Privacy Policy. Guideline 3.1.2, and also just the decent way to sell something.
//
//  **No price, period or saving is written in this file.** They arrive already formatted on
//  `PlanOffer`, computed from the athlete's own storefront. If a price changes in App Store
//  Connect this screen follows without a build, and it cannot drift out of agreement with what
//  the store will actually charge.
//
//  The benefit list and the button change with the selection, because the yearly plan carries
//  a free trial and the monthly one does not. Selling "Try For Free" on a plan that charges
//  immediately is the one mistake here that takes real money from somebody who was told it
//  would not.
//

import SwiftUI

struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(PremiumGate.self) private var gate
    @Environment(\.dismiss) private var dismiss

    /// Yearly is preselected: it carries the trial, and it is the better deal.
    @State private var selected: PremiumTerm = .yearly
    @State private var legalDocument: LegalDocument?

    private var offer: PlanOffer? { store.offers.first { $0.term == selected } }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                benefits
                plans
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { purchaseZone }
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            if store.offers.isEmpty { await store.loadProducts() }
        }
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(document: document, showsDoneButton: true) }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accent, Color.accentPress],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            Text("Replog Premium")
                .font(.rounded(30, .black)).foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("Train every day, and keep every number you log.")
                .font(.rounded(15, .semibold)).foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
    }

    // MARK: - Benefits

    /// The first line changes: a trial is the strongest thing we can lead with, and it is only
    /// true of the plan that actually has one.
    private var benefitLines: [String] {
        var lines: [String] = []
        if let trial = offer?.freeTrialText { lines.append("\(trial) free trial") }
        lines.append("Train and log every day")
        if lines.count < 3 { lines.append("Your full history and progress") }
        lines.append("Cancel anytime from the app")
        return lines
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefitLines, id: \.self) { line in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black)).foregroundStyle(Color.accent)
                        .frame(width: 20)
                    Text(line).font(.rounded(15, .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: benefitLines)
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if store.offers.isEmpty {
            // No invented prices, ever. Until the store answers there is nothing honest to show.
            VStack(spacing: 10) {
                ProgressView().controlSize(.large).tint(.accent)
                Text("Loading plans…")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 36)
        } else {
            VStack(spacing: 12) {
                ForEach(store.offers) { offer in
                    PlanOptionRow(offer: offer, isSelected: offer.term == selected) {
                        withAnimation(.snappy) { selected = offer.term }
                    }
                }
            }
        }
    }

    // MARK: - The ask

    private var purchaseZone: some View {
        VStack(spacing: 10) {
            if let error = store.lastError {
                Text(error)
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.down)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: offer?.callToAction ?? "Subscribe Now") { buy() }
                .disabled(offer == nil || store.purchasing != nil)
                .opacity(offer == nil || store.purchasing != nil ? 0.6 : 1)
                .overlay {
                    if store.purchasing != nil {
                        ProgressView().tint(.white)
                    }
                }

            // Apple requires the exact charge to be stated next to the button that triggers it.
            if let offer {
                Text(offer.chargeDisclosure)
                    .font(.rounded(13, .heavy)).foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text("Renews automatically. Cancel any time.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)

            footerLinks
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var footerLinks: some View {
        HStack(spacing: 10) {
            Button("Restore") { Task { await store.restore(); dismissIfEntitled() } }
            dot
            Button("Terms") { legalDocument = .termsOfUse }
            dot
            Button("Privacy") { legalDocument = .privacyPolicy }
        }
        .font(.rounded(13, .heavy))
        .foregroundStyle(Color.text2)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var dot: some View {
        Text("·").font(.rounded(13, .heavy)).foregroundStyle(Color.text3)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .black)).foregroundStyle(Color.text2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.surface))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.trailing, 20)
        .accessibilityLabel("Close")
    }

    // MARK: - Actions

    private func buy() {
        guard let term = offer?.term else { return }
        Task {
            await store.purchase(term)
            dismissIfEntitled()
        }
    }

    /// Closes the paywall only once the athlete is genuinely entitled, and lets the gate finish
    /// whatever they were trying to do when it appeared.
    private func dismissIfEntitled() {
        guard store.isPremium else { return }
        gate.isPremium = true
        gate.didSubscribe()
    }
}
