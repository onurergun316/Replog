//
//  ReportComposer.swift
//  Replog
//
//  Renders a `PlanReport` (from Apple Intelligence or the deterministic fallback) into the
//  saved markdown the user reads — now with a per-day breakdown that explains EVERY exercise.
//  Also builds a personalized fallback report so a report always exists. Pure & testable.
//

import Foundation

enum ReportComposer {

    /// Renders a report + plan into reader-facing markdown.
    static func markdown(report: PlanReport, plan: GeneratedPlan) -> String {
        var out = "# \(plan.headline)\n\n"
        out += "\(report.philosophy)\n\n"

        out += "## Why this split\n\(report.whyThisSplit)\n\n"

        out += "## Your training week\n"
        for note in report.perDay {
            out += "### \(note.dayName)\n"
            if !note.text.isEmpty { out += "\(note.text)\n\n" }
            for ex in note.exercises {
                out += "- **\(ex.name)** — \(ex.reason)\n"
            }
            out += "\n"
        }

        out += "## The science\n\(report.scienceNotes)\n\n"
        out += "## Staying safe\n\(report.safetyNotes)\n\n"
        out += "> \(report.encouragement)\n"
        return out
    }

    /// A complete, personalized fallback report built from the quiz answers and chosen plan,
    /// including a per-exercise breakdown (names derived from the catalog exercise ids).
    static func fallbackReport(answers: QuizAnswers, plan: GeneratedPlan) -> PlanReport {
        let name = answers.firstName.trimmingCharacters(in: .whitespaces)
        let greeting = name.isEmpty ? "" : "\(name), "
        let days = answers.daysPerWeek
        let goal = answers.goal.displayName.lowercased()

        let philosophy =
            "\(greeting.capitalizedFirst)we built this plan around your goal to \(goal), training " +
            "\(days) day\(days == 1 ? "" : "s") a week as a \(answers.experience.displayName.lowercased()) lifter. " +
            "Every choice is grounded in exercise science — the aim is steady, sustainable progress " +
            "while respecting your recovery and your time."

        let whyThisSplit =
            "We chose a \(plan.name) structure with \(plan.workouts.count) training day\(plan.workouts.count == 1 ? "" : "s"). " +
            "Grouping related muscles into the same session lets each muscle be trained hard, then " +
            "fully recover before its next session — research shows hitting each muscle roughly twice " +
            "a week maximizes muscle protein synthesis without overreaching."

        let perDay = plan.workouts.map { workout -> PerDayNote in
            let notes = workout.items.enumerated().map { i, item in
                ExerciseNote(name: prettyName(item.exId), reason: fallbackReason(index: i))
            }
            return PerDayNote(
                dayName: workout.name,
                text: "These movements share a function, so synergists warm up and fatigue together " +
                      "and recover as a unit.",
                exercises: notes
            )
        }

        let repWindow: String
        switch answers.goal {
        case .buildMuscle, .recomp: repWindow = "8-12 reps, the hypertrophy sweet spot"
        case .loseWeight: repWindow = "higher reps (12-15) to keep density and calorie burn up"
        case .sport: repWindow = "lower reps (6-8) to bias strength and power"
        }
        let scienceNotes =
            "Progress comes from progressive overload: add a little weight or a rep when a set feels " +
            "easier than your target RPE. We program \(repWindow), and use RPE (rate of perceived " +
            "exertion) so you autoregulate — pushing hard on good days and backing off when tired, " +
            "which the evidence links to better long-term gains and fewer injuries."

        let safetyNotes: String
        if answers.injuries.isEmpty {
            safetyNotes =
                "Warm up before your first heavy set, keep one or two reps in reserve early in a " +
                "session, and prioritize sleep — that's when adaptation actually happens."
        } else {
            let list = answers.injuries.map(\.displayName).joined(separator: ", ")
            safetyNotes =
                "You told us about: \(list). We deliberately avoided loading those areas as primary " +
                "movers and chose joint-friendly alternatives. Stop any movement that causes sharp " +
                "pain and give those areas extra warm-up time."
        }

        let encouragement =
            "\(greeting.capitalizedFirst)your health and consistency matter more than any single session — " +
            "show up, log your sets, and let the progress compound. We've got you."

        return PlanReport(
            philosophy: philosophy,
            whyThisSplit: whyThisSplit,
            perDay: perDay,
            scienceNotes: scienceNotes,
            safetyNotes: safetyNotes,
            encouragement: encouragement
        )
    }

    /// Convenience: a fully-rendered fallback markdown report.
    static func fallbackMarkdown(answers: QuizAnswers, plan: GeneratedPlan) -> String {
        markdown(report: fallbackReport(answers: answers, plan: plan), plan: plan)
    }

    // MARK: - Helpers

    /// Turns a catalog id ("Alternating_Floor_Press") into a display name ("Alternating Floor Press").
    static func prettyName(_ exId: String) -> String {
        exId.replacingOccurrences(of: "_", with: " ")
    }

    private static func fallbackReason(index: Int) -> String {
        index == 0
            ? "Your primary compound lift for this day — the biggest driver of strength and size."
            : "Accessory work that adds focused volume and rounds out the day's stimulus."
    }
}

private extension String {
    /// Capitalizes only the first character (so "alex, we…" → "Alex, we…").
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
