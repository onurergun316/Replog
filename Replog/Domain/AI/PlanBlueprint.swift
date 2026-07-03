//
//  PlanBlueprint.swift
//  Replog
//
//  Structured output types for Apple Intelligence, program-driven plan generation. Generation
//  happens in two stages so the model genuinely drives the plan and can justify every choice:
//
//   1. ProgramFraming — the model picks ONE program from a numbered shortlist of real library
//      candidates and writes the report's overall sections (philosophy, science, safety…).
//   2. DaySelection — for each program day, the model picks a real catalog exercise per slot
//      (by candidate number) and gives a reason for each.
//
//  `@Generable` makes these usable with FoundationModels guided generation. They are plain
//  value types otherwise, so the resolver, report composer, and tests use them with no model.
//

import Foundation
import FoundationModels

/// Stage 1 for program-driven planning: the model picks ONE program from a numbered
/// shortlist of real library candidates and writes the report's overall sections. The split
/// itself is no longer invented — it comes from the chosen program's days.
@Generable
struct ProgramFraming: Equatable, Sendable {
    @Guide(description: "The number of the single best program for this person from the provided candidate list.")
    var chosenProgramNumber: Int

    @Guide(description: "One sentence: why this program is the best fit for this person's goal, experience, schedule, and equipment.")
    var justification: String

    @Guide(description: "A motivating headline for the plan, e.g. 'Your Muscle-Building Plan'.")
    var headline: String

    @Guide(description: "3-4 sentences on the training philosophy behind this program, tailored to this person's goal, level, and body.")
    var philosophy: String

    @Guide(description: "3-5 sentences explaining WHY this program's structure works, with the science (frequency, recovery, progressive overload), in plain language.")
    var whyThisSplit: String

    @Guide(description: "3-5 sentences on the evidence-based principles behind the program (weekly volume, rep ranges, RPE autoregulation, its progression rule), in plain language.")
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
