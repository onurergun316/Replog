//
//  PlanBlueprint.swift
//  Replog
//
//  The structured output Apple Intelligence produces for a training plan. The model
//  decides the *programming* (split, per-day muscle focus, volume, rep/RPE schemes) and
//  the rationale; the deterministic `PlanResolver` then maps each day's muscle targets
//  onto real catalog exercises so images/refs are always valid (the "hybrid" approach).
//
//  `@Generable` makes these types usable with FoundationModels guided generation. They
//  are plain value types otherwise, so the resolver, report composer, and unit tests use
//  them without any model at runtime.
//

import Foundation
import FoundationModels

/// One training day as decided by the model.
@Generable
struct WorkoutBlueprint: Equatable, Sendable {
    @Guide(description: "Name of the training day, e.g. 'Push Day' or 'Upper Body'.")
    var name: String

    @Guide(description: "Primary muscle groups trained this day, lowercase single words like 'chest', 'shoulders', 'triceps', 'quadriceps', 'lats'. 2 to 4 groups.")
    var targetMuscles: [String]

    @Guide(description: "How many exercises this day should contain, between 3 and 6.")
    var exerciseCount: Int

    @Guide(description: "Target repetitions per working set, typically 6 to 15 depending on goal.")
    var reps: Int

    @Guide(description: "Target RPE (rate of perceived exertion) per set, an integer from 6 to 10.")
    var rpe: Int

    @Guide(description: "Number of working sets per exercise, typically 3 or 4.")
    var sets: Int

    @Guide(description: "One or two sentences explaining why this day is grouped this way and which muscles are trained together.")
    var rationale: String
}

/// The full plan blueprint plus the coach's report sections.
@Generable
struct PlanBlueprint: Equatable, Sendable {
    @Guide(description: "A short, catchy plan name, e.g. 'Push · Pull · Legs' or 'Upper / Lower'.")
    var planName: String

    @Guide(description: "A motivating headline, e.g. 'Your Hypertrophy Plan'.")
    var headline: String

    @Guide(description: "The training days in order. Exactly one entry per scheduled training day.")
    var workouts: [WorkoutBlueprint]

    @Guide(description: "2-3 sentences on the overall training philosophy tailored to this person's goal and level.")
    var philosophy: String

    @Guide(description: "2-3 sentences explaining why this particular split/structure was chosen for their schedule, with the science (e.g. weekly frequency, recovery, muscle protein synthesis).")
    var whyThisSplit: String

    @Guide(description: "2-4 sentences citing the evidence-based principles behind the plan (progressive overload, volume landmarks, rep ranges, RPE autoregulation), written in plain language.")
    var scienceNotes: String

    @Guide(description: "1-3 sentences on safety, recovery, and any adaptations made for stated injuries or limitations. If none, give general joint-friendly guidance.")
    var safetyNotes: String

    @Guide(description: "1-2 warm, encouraging sentences that show you care about this person's health and progress.")
    var encouragement: String
}

// MARK: - Render-ready report (decoupled from FoundationModels)

/// A per-day rationale entry in the report.
struct PerDayNote: Equatable, Sendable {
    var dayName: String
    var text: String
}

/// A plan report ready to render to markdown. Built either from an AI `PlanBlueprint` or
/// from the deterministic fallback, so a report always exists.
struct PlanReport: Equatable, Sendable {
    var philosophy: String
    var whyThisSplit: String
    var perDay: [PerDayNote]
    var scienceNotes: String
    var safetyNotes: String
    var encouragement: String

    /// Builds a report from an AI blueprint (per-day notes come from each day's rationale).
    init(blueprint: PlanBlueprint) {
        philosophy = blueprint.philosophy
        whyThisSplit = blueprint.whyThisSplit
        perDay = blueprint.workouts.map { PerDayNote(dayName: $0.name, text: $0.rationale) }
        scienceNotes = blueprint.scienceNotes
        safetyNotes = blueprint.safetyNotes
        encouragement = blueprint.encouragement
    }

    init(philosophy: String, whyThisSplit: String, perDay: [PerDayNote],
         scienceNotes: String, safetyNotes: String, encouragement: String) {
        self.philosophy = philosophy
        self.whyThisSplit = whyThisSplit
        self.perDay = perDay
        self.scienceNotes = scienceNotes
        self.safetyNotes = safetyNotes
        self.encouragement = encouragement
    }
}
