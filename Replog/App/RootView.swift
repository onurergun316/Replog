//
//  RootView.swift
//  Replog
//
//  Decides between onboarding and the main app, applies the user's color scheme,
//  and presents the active workout full-screen when one is in progress.
//
//  It also keeps `PremiumGate` fed and owns the app's single paywall sheet. The gate
//  deliberately does not read SwiftData or StoreKit itself — this is the one view that already
//  has both, so this is where the two values are copied across. One sheet, at the root, means
//  the paywall can be raised from any screen without every screen carrying its own copy.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(PremiumGate.self) private var gate
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AppSettings]
    @Query private var activeSessions: [ActiveSession]

    // Read-only: the singletons are bootstrapped in ReplogApp.init, so body never mutates the context.
    private var onboardingDone: Bool { profiles.first?.onboardingDone ?? false }
    private var darkMode: Bool { settings.first?.darkMode ?? false }
    private var freeDayDate: Date? { settings.first?.freeDayDate }

    var body: some View {
        @Bindable var gate = gate

        Group {
            if onboardingDone {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .tint(.accent)
        .preferredColorScheme(darkMode ? .dark : .light)
        .fullScreenCover(item: Binding(
            get: { activeSessions.first(where: \.isOpen) },
            set: { newValue in
                // Cover dismissed (e.g. swipe) → pause the session, don't destroy it.
                if newValue == nil { activeSessions.first(where: \.isOpen)?.isOpen = false }
            }
        )) { session in
            ActiveWorkoutView(session: session)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
        .sheet(isPresented: $gate.isPaywallPresented) {
            PaywallView()
                .preferredColorScheme(darkMode ? .dark : .light)
        }
        .task {
            subscriptions.start()
            syncGate()
        }
        .onChange(of: subscriptions.isPremium) { _, _ in syncGate() }
        .onChange(of: freeDayDate) { _, _ in syncGate() }
        #if DEBUG
        .onAppear {
            DebugSeed.seedIfNeeded(context)
            gate.debugOverride = DebugSeed.accessOverride
        }
        #endif
    }

    /// Copies the gate's two inputs across from the store and from settings.
    private func syncGate() {
        gate.isPremium = subscriptions.isPremium
        gate.freeDayDate = freeDayDate
    }
}
