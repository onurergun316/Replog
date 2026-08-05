//
//  ReviewPrompt.swift
//  Replog
//
//  When to ask for a rating.
//
//  Three completed training days, once, ever. Three is the point at which somebody has
//  actually used the app rather than looked at it, and it is late enough that the answer
//  means something — a prompt on day one measures the onboarding, not the product.
//
//  It counts *days*, not sessions, because `UserProfile.doneDates` already records exactly
//  that and three workouts in one afternoon is not three days of using an app.
//
//  The prompt itself is Apple's. We never show our own stars and route the good ones to the
//  App Store: guideline 1.1.7 exists precisely to stop that, and a rating you filtered for is
//  not information you can act on anyway.
//

import Foundation

enum ReviewPrompt {

    /// Completed training days before asking.
    static let requiredDays = 3

    /// Whether to request a review now.
    ///
    /// `alreadyRequested` is persisted on `AppSettings`, so the answer survives relaunch.
    /// iOS additionally throttles the prompt and may show nothing at all; that is expected
    /// and deliberately not worked around — retrying until it lands is how an app starts
    /// feeling like it is nagging.
    static func shouldRequest(completedDayCount: Int, alreadyRequested: Bool) -> Bool {
        !alreadyRequested && completedDayCount >= requiredDays
    }
}
