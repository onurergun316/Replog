//
//  SessionCompletion.swift
//  Replog
//
//  What a finished session still has to say once the workout screen has gone.
//
//  Finishing DELETES the `ActiveSession` (`SessionFinisher`), and the workout is presented
//  as a `fullScreenCover(item:)` bound to that very session — so the instant the finish
//  lands, the screen that was hosting the celebration is being torn down. Anything the
//  workout view presented for itself went with it, which is why the badge moment, the
//  loudest thing the app has to offer, could flash and vanish before it was ever seen.
//
//  So the payload outlives the screen. `ActiveWorkoutView` hands over what it earned and
//  dismisses; `RootView` — which is still there — plays it back once the cover is gone.
//
//  The order is the athlete's dopamine, not ours: the badge detonates first, immediately
//  after Save & Finish, because that is the rare thing; the coach's debrief is the calm
//  read that follows it.
//
//  Kept as a plain state machine with no SwiftUI in it, so the whole sequence — including
//  "nothing was earned, get out of the way" — is unit-testable.
//

import Foundation

@MainActor
@Observable
final class SessionCompletion {

    /// Where the post-session sequence is. `idle` means the app is simply itself again.
    enum Stage: Equatable {
        case idle
        /// The badge celebration overlay is up.
        case badges
        /// The coach debrief sheet is up.
        case debrief
    }

    private(set) var stage: Stage = .idle
    /// Badges earned by the session being celebrated. Empty unless `stage == .badges`.
    private(set) var badges: [Badge] = []
    /// The debrief's insights. Held from `finished(…)` so they survive the badge stage.
    private(set) var insights: [CoachInsight] = []

    /// Held from the finish until the workout cover has actually gone. Presenting into a
    /// hierarchy that is mid-dismissal is how the celebration got lost in the first place.
    private var pending: (badges: [Badge], insights: [CoachInsight])?

    /// Whether a finished session is still waiting to be celebrated — true between the
    /// finish and `presentPending()`.
    var hasPending: Bool { pending != nil }

    /// Whether anything at all is on screen because of a finished session.
    var isPresenting: Bool { stage != .idle }

    // MARK: - Intents

    /// Records what a just-finished session earned. Nothing is shown yet: the workout is
    /// still on screen at this point and is about to dismiss itself.
    func finished(badges: [Badge], insights: [CoachInsight]) {
        guard !badges.isEmpty || !insights.isEmpty else {
            pending = nil
            return
        }
        pending = (badges, insights)
    }

    /// Starts the sequence, if there is one. Called when the workout cover has finished
    /// dismissing. Returns whether anything was raised, so the caller can tell "the
    /// celebration has the screen" from "the athlete is simply back on Today".
    @discardableResult
    func presentPending() -> Bool {
        guard let pending else { return false }
        self.pending = nil
        badges = pending.badges
        insights = pending.insights
        stage = badges.isEmpty ? .debrief : .badges
        return true
    }

    /// Moves to whatever comes next: badges hand over to the debrief, the debrief ends the
    /// sequence. Called when the athlete dismisses whatever is currently up.
    func advance() {
        switch stage {
        case .badges:
            stage = insights.isEmpty ? .idle : .debrief
            if stage == .idle { clear() }
        case .debrief:
            stage = .idle
            clear()
        case .idle:
            break
        }
    }

    /// Ends the sequence wherever it is — for a hard reset (a new session starting, data
    /// wiped) rather than a normal dismissal.
    func reset() {
        pending = nil
        stage = .idle
        clear()
    }

    private func clear() {
        badges = []
        insights = []
    }
}
