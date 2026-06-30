//
//  RootView.swift
//  Replog
//
//  Decides between onboarding and the main app, applies the user's color scheme,
//  and presents the active workout full-screen when one is in progress.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AppSettings]
    @Query private var activeSessions: [ActiveSession]

    // Read-only: the singletons are bootstrapped in ReplogApp.init, so body never mutates the context.
    private var onboardingDone: Bool { profiles.first?.onboardingDone ?? false }
    private var darkMode: Bool { settings.first?.darkMode ?? false }

    var body: some View {
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
            get: { activeSessions.first },
            set: { _ in }
        )) { session in
            ActiveWorkoutView(session: session)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
        #if DEBUG
        .onAppear { DebugSeed.seedIfNeeded(context) }
        #endif
    }
}
