//
//  PremiumGate.swift
//  Replog
//
//  The thing every screen actually talks to. One question, one answer, one paywall.
//
//  `AccessPolicy` decides, `SubscriptionStore` knows about money and `AppSettings` knows about
//  the free day; this holds the two inputs together, answers "may they?", and owns the single
//  paywall sheet the whole app shares. Call sites get one extra word:
//
//      Button("Start Workout") { gate.require { start(workout) } }
//
//  `require` runs the closure when unlocked, and otherwise keeps it, opens the paywall, and
//  runs it if they subscribe — so buying Premium from a Start button starts the workout,
//  rather than dumping you back on the screen to tap the same button again.
//
//  It mirrors its two inputs rather than reaching for them. It could hold a `SubscriptionStore`
//  and a `ModelContext` and read both itself, but then the gate would own SwiftData access,
//  which this codebase deliberately keeps in the View, and it would be impossible to test
//  without a store. Two plain properties that `RootView` keeps current is duller and better.
//

import Foundation
import Observation

@MainActor
@Observable
final class PremiumGate {

    // MARK: - Inputs, mirrored from elsewhere

    /// Whether StoreKit says they are entitled. Kept current by `RootView`.
    var isPremium = false

    /// The single day a free athlete may train, from `AppSettings`. Kept current by `RootView`.
    var freeDayDate: Date?

    /// Forces an answer regardless of the inputs. DEBUG-only, for visual checks of the locked
    /// and subscribed states without buying anything or waiting for midnight.
    var debugOverride: Access?

    /// The moment `access` is judged against.
    ///
    /// It has to be stored rather than read live. `access` depends on today's date, but
    /// neither of the inputs above changes at midnight — so with a live `Date()` an app left
    /// open overnight would keep answering "free day" until something unrelated happened to
    /// redraw it. `revalidate()` advances this on foreground, which is the same trigger
    /// `TodayView.reanchorIfNeeded` uses to re-anchor its week strip.
    private(set) var asOf: Date = Date()

    // MARK: - Paywall presentation

    /// Bound directly by `RootView`'s sheet. Writable so a swipe-down works like any other
    /// dismissal; the observer makes sure a dismissed paywall never leaves a stale action
    /// waiting to fire at some unrelated moment later.
    var isPaywallPresented = false {
        didSet { if !isPaywallPresented { pending = nil } }
    }

    /// What to run if they subscribe.
    private var pending: (() -> Void)?

    // MARK: - The answer

    var access: Access {
        debugOverride ?? AccessPolicy.access(isPremium: isPremium, freeDayDate: freeDayDate, now: asOf)
    }

    /// Re-judges access against the current moment. Call on foreground.
    func revalidate() { asOf = Date() }

    /// Whether writes are allowed. The question every call site asks.
    var isUnlocked: Bool { access.isUnlocked }

    /// True only for a free athlete who has spent their day — the state the read-only copy
    /// around the app is written for.
    var isLocked: Bool { access == .locked }

    /// Whether a session begun on `startedAt` may still be logged and finished.
    /// A workout started on the free day stays finishable; see `AccessPolicy`.
    func allowsFinishing(sessionStartedAt: Date) -> Bool {
        if let debugOverride { return debugOverride.isUnlocked }
        return AccessPolicy.allowsFinishing(sessionStartedAt: sessionStartedAt,
                                            isPremium: isPremium, freeDayDate: freeDayDate)
    }

    // MARK: - Gating

    /// Runs `action` when unlocked. Otherwise opens the paywall and runs it only if they subscribe.
    func require(_ action: @escaping () -> Void) {
        guard !isUnlocked else { return action() }
        pending = action
        isPaywallPresented = true
    }

    /// Opens the paywall with nothing waiting behind it — the Profile row, and the one
    /// showing after onboarding.
    func presentPaywall() {
        pending = nil
        isPaywallPresented = true
    }

    /// Called by the paywall once a purchase has actually entitled them: closes the sheet and
    /// completes whatever they were trying to do.
    ///
    /// The action is captured before dismissing, because dismissing clears it.
    func didSubscribe() {
        let action = pending
        isPaywallPresented = false
        action?()
    }
}
