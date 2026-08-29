//
//  RootView.swift
//  Replog
//
//  Decides between onboarding and the main app, applies the user's color scheme,
//  and presents the active workout full-screen when one is in progress.
//
//  It also plays back what a finished session earned — the badge celebration, then the
//  coach's debrief. That lives here rather than in the workout screen because finishing
//  DELETES the session the cover is bound to, so the workout view is being torn down at
//  the exact moment it would have celebrated (`SessionCompletion`).
//
//  It also keeps `PremiumGate` fed and owns the app's single paywall sheet. The gate
//  deliberately does not read SwiftData or StoreKit itself — this is the one view that already
//  has both, so this is where the two values are copied across. One sheet, at the root, means
//  the paywall can be raised from any screen without every screen carrying its own copy.
//

import SwiftUI
import SwiftData
import StoreKit

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(PremiumGate.self) private var gate
    @Environment(\.requestReview) private var requestReview
    @Query private var profiles: [UserProfile]
    @Query private var settings: [AppSettings]
    @Query private var activeSessions: [ActiveSession]

    /// What a just-finished session still has to show. Owned here, and not in the workout
    /// screen, because finishing deletes the session the cover below is bound to: the
    /// celebration has to outlive the screen that earned it.
    @State private var completion = SessionCompletion()

    #if DEBUG
    /// One-shot guard for the `REPLOG_BADGE` preview: `onAppear` can fire more than once,
    /// and re-raising the celebration every time is not what "show me the moment" means.
    @State private var didPreviewBadges = false
    #endif

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
            // `isOpen` alone is not enough. It is a stored flag any caller could flip, and the
            // screen behind this cover carries no gate of its own — presenting it IS granting
            // every write in the logging loop. Asking `allowsFinishing` here means a session
            // the athlete may not finish can never be presented, whoever set the flag.
            get: { activeSessions.first { $0.isOpen && gate.allowsFinishing(sessionStartedAt: $0.startedAt) } },
            set: { newValue in
                // Cover dismissed (e.g. swipe) → pause the session, don't destroy it.
                if newValue == nil { activeSessions.first(where: \.isOpen)?.isOpen = false }
            }
        ), onDismiss: workoutCoverDismissed) { session in
            ActiveWorkoutView(session: session) { badges, insights in
                completion.finished(badges: badges, insights: insights)
            }
            .preferredColorScheme(darkMode ? .dark : .light)
        }
        // The badge lands first, the instant the workout screen is out of the way: it is the
        // rarer thing, and it is what the athlete just tapped Finish for. The coach's debrief
        // is the calm read that follows it.
        .overlay {
            if completion.stage == .badges {
                BadgeCelebrationOverlay(badges: completion.badges) {
                    withAnimation(.snappy) { completion.advance() }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: Binding(get: { completion.stage == .debrief },
                                    set: { if !$0 { completion.advance() } })) {
            NavigationStack { CoachDebriefView(insights: completion.insights) }
                .preferredColorScheme(darkMode ? .dark : .light)
        }
        // The rating ask waits for the whole sequence, never lands on top of it.
        .onChange(of: completion.stage) { previous, current in
            if previous != .idle, current == .idle { requestReviewIfEarned() }
        }
        // The two shared objects are handed to the sheet explicitly rather than left to
        // inherit. Presented content is hosted outside this view's hierarchy, and on
        // "My Mac (Designed for iPad)" the `@Observable` objects injected up in
        // `ReplogApp`'s WindowGroup did not reach it: opening the paywall right after
        // onboarding trapped in `Environment+Objects.swift` with "No Observable object of
        // type SubscriptionStore found", with the app already on screen behind it.
        //
        // The asymmetry is what identified it. `ActiveWorkoutView` above is presented the
        // same way and never failed, because it reads only key-path environment values
        // (`\.modelContext`, `\.exerciseCatalog`) — those propagate into presentations;
        // the object-based ones did not. `PaywallView` is the only thing this view
        // presents that needs them, and it is the only thing that crashed.
        //
        // This view demonstrably holds both objects — it renders, and `.task` below calls
        // `subscriptions.start()` on one of them — so passing its own copies down cannot
        // fail, whatever SwiftUI is doing with inheritance across a presentation boundary.
        .sheet(isPresented: $gate.isPaywallPresented) {
            PaywallView()
                .environment(subscriptions)
                .environment(gate)
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
            if !didPreviewBadges, let badges = DebugSeed.sampleUnlockedBadges {
                didPreviewBadges = true
                completion.finished(badges: badges, insights: [])
                completion.presentPending()
            }
        }
        #endif
    }

    /// Copies the gate's two inputs across from the store and from settings, then makes sure a
    /// stale session cannot reopen itself.
    private func syncGate() {
        gate.isPremium = subscriptions.isPremium
        gate.freeDayDate = freeDayDate
        parkUnfinishableSession()
    }

    /// Pauses an open session the athlete is no longer entitled to finish.
    ///
    /// Closing a workout with "X" sets `isOpen = false`, and so does swiping the cover away —
    /// but **force-quitting mid-workout leaves it true**. Without this, an athlete whose access
    /// lapsed while a session was open would be dropped straight back into a writable workout
    /// on every launch, for good, since the cover presents on `isOpen` alone.
    ///
    /// Parking it rather than deleting it keeps their logged sets: Today then shows "Continue",
    /// which asks the gate like every other way back in.
    private func parkUnfinishableSession() {
        guard let open = activeSessions.first(where: \.isOpen),
              !gate.allowsFinishing(sessionStartedAt: open.startedAt) else { return }
        open.isOpen = false
        try? context.save()
    }

    /// The workout cover has gone. Anything the session earned is raised now — and only
    /// now, because presenting into a hierarchy that is mid-dismissal is exactly how the
    /// badge moment used to be lost. With nothing to celebrate, this is the calm moment the
    /// rating ask was always meant to use.
    private func workoutCoverDismissed() {
        if !completion.presentPending() { requestReviewIfEarned() }
    }

    /// Asks for a rating once the athlete has three real training days behind them.
    ///
    /// Fired when the workout cover closes, which is the calmest moment the app has — never
    /// mid-session, never over the celebration or the badge. **A pause leaves the session in
    /// the store and a finish deletes it**, so an empty store here is what distinguishes
    /// "they finished" from "they stepped away", and only the former earns the ask.
    private func requestReviewIfEarned() {
        guard activeSessions.isEmpty,
              let profile = profiles.first, let settings = settings.first,
              ReviewPrompt.shouldRequest(completedDayCount: profile.doneDates.count,
                                         alreadyRequested: settings.hasRequestedReview)
        else { return }

        // Written down before asking, not after. iOS may decline to show the prompt at all,
        // and re-asking on every future finish because it stayed invisible is exactly the
        // nagging this is supposed to avoid.
        settings.hasRequestedReview = true
        try? context.save()

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            requestReview()
        }
    }
}
