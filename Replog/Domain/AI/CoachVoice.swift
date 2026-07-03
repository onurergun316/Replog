//
//  CoachVoice.swift
//  Replog
//
//  Optional Apple Intelligence pass that rewords a deterministic `CoachInsight` into a warmer
//  coach voice. Policy identical to the planner: the model NEVER invents the decision — it only
//  rephrases the already-reasoned text, and the deterministic body is used verbatim whenever the
//  model is unavailable or errors. This keeps every recommendation explainable and grounded.
//

import Foundation
import FoundationModels

@MainActor
struct CoachVoice {

    /// Forces the deterministic path (tests + when the user is offline model-wise).
    let forceFallback: Bool
    let temperature: Double

    nonisolated init(forceFallback: Bool = false, temperature: Double = 0.6) {
        self.forceFallback = forceFallback
        self.temperature = temperature
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Returns a copy of `insight` with its `body` reworded in coach voice, or the original
    /// verbatim if the model is unavailable/errors. The facts (title, metrics, tags) are never
    /// changed — only the phrasing of the reason.
    func reword(_ insight: CoachInsight) async -> CoachInsight {
        guard !forceFallback, Self.isAvailable else { return insight }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let reworded = try await session.respond(
                to: Self.prompt(for: insight),
                options: GenerationOptions(temperature: temperature)
            ).content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reworded.isEmpty else { return insight }
            var copy = insight
            copy.body = reworded
            return copy
        } catch {
            return insight
        }
    }

    /// Rewords a batch (each independently); order preserved.
    func reword(_ insights: [CoachInsight]) async -> [CoachInsight] {
        var out: [CoachInsight] = []
        for insight in insights { out.append(await reword(insight)) }
        return out
    }

    // MARK: - Prompt

    static let instructions = """
    You are a warm, encouraging strength coach. You will be given a factual coaching note that has \
    already been decided by a deterministic engine. Rephrase ONLY its wording into a warm, concise, \
    plain-language sentence or two. Never change the numbers, the recommendation, or the meaning — \
    do not invent anything. Keep it under 45 words.
    """

    static func prompt(for insight: CoachInsight) -> String {
        """
        Coaching note titled "\(insight.title)":
        \(insight.body)

        Rewrite the note above in a warm coach voice, keeping every fact and the recommendation identical.
        """
    }
}
