//
//  PlanBlueprint.swift
//  Replog
//
//  Structured output types for Apple Intelligence plan generation. Generation happens in
//  two stages so the model genuinely drives the plan and can justify every choice:
//
//   1. PlanFraming — the model designs the split: per-day muscle focus, volume, rep/RPE
//      scheme, plus the report's overall sections (philosophy, why-this-split, science…).
//   2. DaySelection — for each day, the model picks SPECIFIC exercises (by candidate number)
//      from a list of real catalog exercises and gives a reason for each.
//
//  `@Generable` makes these usable with FoundationModels guided generation. They are plain
//  value types otherwise, so the resolver, report composer, and tests use them with no model.
//

import Foundation
import FoundationModels

/// One training day's programming, as designed by the model (no exercises yet).
@Generable
struct DayFraming: Equatable, Sendable {
    @Guide(description: "Name of the training day, e.g. 'Push Day' or 'Upper Body'.")
    var name: String

    @Guide(description: "This day's 2-4 primary muscle groups, lowercase single words like 'chest', 'shoulders', 'triceps', 'quadriceps', 'lats'.")
    var targetMuscles: [String]

    @Guide(description: "How many exercises this day should contain, between 3 and 6.")
    var exerciseCount: Int

    @Guide(description: "Target repetitions per working set, typically 6 to 15 depending on goal.")
    var reps: Int

    @Guide(description: "Target RPE (rate of perceived exertion) per set, an integer from 6 to 10.")
    var rpe: Int

    @Guide(description: "Number of working sets per exercise, typically 3 or 4.")
    var sets: Int
}

/// The overall plan framing + report sections.
@Generable
struct PlanFraming: Equatable, Sendable {
    @Guide(description: "A short, catchy plan name, e.g. 'Push · Pull · Legs' or 'Upper / Lower'.")
    var planName: String

    @Guide(description: "A motivating headline, e.g. 'Your Hypertrophy Plan'.")
    var headline: String

    @Guide(description: "The training days in order. Exactly one entry per scheduled training day.")
    var workouts: [DayFraming]

    @Guide(description: "3-4 sentences on the overall training philosophy, tailored to this person's goal, level, and body.")
    var philosophy: String

    @Guide(description: "3-5 sentences explaining WHY this split and WHY these muscles are paired on the same day, with the science (weekly frequency, recovery, antagonist pairing, muscle protein synthesis).")
    var whyThisSplit: String

    @Guide(description: "3-5 sentences on the evidence-based principles (progressive overload, weekly volume landmarks, rep ranges, RPE autoregulation), in plain language.")
    var scienceNotes: String

    @Guide(description: "2-4 sentences on safety, recovery, and adaptations for any stated injuries or limitations. If none, give joint-friendly guidance.")
    var safetyNotes: String

    @Guide(description: "2-3 warm, encouraging sentences showing genuine care for this person's health and progress.")
    var encouragement: String
}

/// One exercise the model chose for a day, by candidate number, with its reasoning.
@Generable
struct ExercisePick: Equatable, Sendable {
    @Guide(description: "The number of the chosen exercise from the provided candidate list.")
    var number: Int

    @Guide(description: "One or two sentences: why you chose this exercise, what it trains, and how it fits this day.")
    var reason: String
}

/// The model's exercise selection for a single day.
@Generable
struct DaySelection: Equatable, Sendable {
    @Guide(description: "2-3 sentences on why these exercises are grouped and ordered this way (e.g. compound first, antagonist pairing, fatigue management).")
    var dayRationale: String

    @Guide(description: "The chosen exercises by candidate number, in the order they should be performed.")
    var picks: [ExercisePick]
}

// MARK: - Render-ready report (decoupled from FoundationModels)

/// One exercise's explanation in the report.
struct ExerciseNote: Equatable, Sendable {
    var name: String
    var reason: String
}

/// A training day in the report: its rationale plus a per-exercise breakdown.
struct PerDayNote: Equatable, Sendable {
    var dayName: String
    var text: String
    var exercises: [ExerciseNote]
}

/// A plan report ready to render to markdown (from Apple Intelligence or the fallback).
struct PlanReport: Equatable, Sendable {
    var philosophy: String
    var whyThisSplit: String
    var perDay: [PerDayNote]
    var scienceNotes: String
    var safetyNotes: String
    var encouragement: String
}
