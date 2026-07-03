//
//  AthleteContext.swift
//  Replog
//
//  A compact, pure digest of the athlete's REAL logged training data, rendered into the
//  on-device planner prompt so the model grounds loads, reps and exercise choices in what
//  the person has actually done — not generic guesses. All math is deterministic and
//  unit-tested; the model only ever sees the rendered summary text.
//
//  The on-device model's context window is small (~4k tokens), so the digest is budgeted:
//  `promptSection(maxTokens:)` drops the least-relevant lifts until the section fits.
//

import Foundation

/// Rough token accounting for prompts sent to the on-device model.
/// FoundationModels exposes no public token counter, so we estimate conservatively at
/// ~3.5 characters per token for English prose (real prose averages nearer 4).
enum PromptBudget {
    /// The on-device model's approximate context window (input + output), in tokens.
    static let contextWindow = 4096
    /// Tokens reserved for the model's structured response.
    static let responseReserve = 1400

    /// Conservative token estimate for a piece of prompt text.
    static func estimatedTokens(_ text: String) -> Int {
        Int((Double(text.count) / 3.5).rounded(.up))
    }

    /// The token count our budgeting uses for a prompt. FoundationModels exposes no public
    /// tokenizer, so this is the on-device proxy the whole planner budgets against.
    static func tokenCount(for text: String) -> Int { estimatedTokens(text) }

    /// The hard ceiling for a single prompt (context window minus the response reserve).
    static var promptLimit: Int { contextWindow - responseReserve }

    /// Tokens left for additional prompt content once the fixed parts and the
    /// response reserve are accounted for. Never negative.
    static func remainingTokens(afterFixed parts: String...) -> Int {
        let used = parts.reduce(0) { $0 + estimatedTokens($1) }
        return max(0, contextWindow - responseReserve - used)
    }
}

/// One lift's recent history, distilled to what a coach needs to program it.
struct LiftDigest: Equatable, Sendable {
    var exId: String
    var name: String
    var lastTopWeightKg: Double
    var lastTopReps: Int
    var currentE1rm: Int
    var bestE1rm: Int
    /// e1RM change of the latest session vs the prior one, or nil with fewer than 2 sessions.
    var trendPercent: Double?
    var sessionCount: Int

    /// Full line for the framing prompt's history section.
    var promptLine: String {
        "\(name): last top set \(Self.kgText(lastTopWeightKg)) kg × \(lastTopReps), " +
        "est 1RM \(currentE1rm) kg (best \(bestE1rm) kg), \(trendText), " +
        "\(sessionCount) session\(sessionCount == 1 ? "" : "s") logged"
    }

    /// Short annotation appended to a matching candidate in the selection prompt.
    var shortNote: String {
        "logged: last \(Self.kgText(lastTopWeightKg)) kg × \(lastTopReps), \(trendText)"
    }

    private var trendText: String {
        guard let trendPercent else { return "no trend yet" }
        if trendPercent > 0 { return String(format: "up %.1f%% vs previous", trendPercent) }
        if trendPercent < 0 { return String(format: "down %.1f%% vs previous", -trendPercent) }
        return "flat vs previous"
    }

    private static func kgText(_ kg: Double) -> String {
        kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg)
    }
}

/// Working sets logged for one muscle over the trailing week.
struct MuscleSetVolume: Equatable, Sendable {
    var muscle: Muscle
    var sets: Int
}

/// The athlete's recent training, summarised for the planner. Pure value type:
/// build it with `make(history:catalog:now:)`, render it with `promptSection(maxTokens:)`.
struct AthleteContext: Equatable, Sendable {
    /// Per-lift digests, most relevant first (most-trained, then most recent).
    var lifts: [LiftDigest] = []
    /// Working sets per primary muscle over the trailing 7 days, highest volume first.
    var weeklySetsPerMuscle: [MuscleSetVolume] = []

    var isEmpty: Bool { lifts.isEmpty }

    // Nonisolated so it can serve as a default argument from any isolation context.
    nonisolated static let empty = AthleteContext()

    /// The digest for a specific catalog exercise, if the athlete has logged it recently.
    func digest(forExId exId: String) -> LiftDigest? {
        lifts.first { $0.exId == exId }
    }

    // MARK: - Building

    /// Summarises history entries within the trailing `windowDays` (stale lifts are not
    /// coaching-relevant), keeping the `maxLifts` most relevant lifts. Entries whose
    /// exercise no longer resolves in the catalog are skipped.
    static func make(history: [HistoryEntry],
                     catalog: ExerciseCatalog,
                     now: Date = Date(),
                     windowDays: Int = 56,
                     maxLifts: Int = 10) -> AthleteContext {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let recent = history.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return .empty }

        // Per-lift digests, reusing the tested progress math.
        var ranked: [(digest: LiftDigest, lastDate: Date)] = []
        for (exId, entries) in Dictionary(grouping: recent, by: \.exId) {
            guard let exercise = catalog.exercise(id: exId),
                  let latest = entries.max(by: { $0.date < $1.date }) else { continue }
            let progress = ProgressAggregator.summarize(exId: exId, history: entries)
            ranked.append((LiftDigest(exId: exId,
                                      name: exercise.name,
                                      lastTopWeightKg: latest.topW,
                                      lastTopReps: latest.topR,
                                      currentE1rm: progress.currentE1rm,
                                      bestE1rm: progress.bestE1rm,
                                      trendPercent: progress.trendPercent,
                                      sessionCount: progress.sessionCount),
                           latest.date))
        }
        ranked.sort {
            if $0.digest.sessionCount != $1.digest.sessionCount {
                return $0.digest.sessionCount > $1.digest.sessionCount
            }
            if $0.lastDate != $1.lastDate { return $0.lastDate > $1.lastDate }
            return $0.digest.name < $1.digest.name
        }

        // Weekly volume per primary muscle (trailing 7 days).
        let weekCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        var setsByMuscle: [Muscle: Int] = [:]
        for entry in recent where entry.date >= weekCutoff {
            guard let exercise = catalog.exercise(id: entry.exId) else { continue }
            let sets = max(entry.sets.count, 1)  // the top set exists even if setsJSON is empty
            for muscle in exercise.primaryMuscles {
                setsByMuscle[muscle, default: 0] += sets
            }
        }
        let weekly = setsByMuscle
            .map { MuscleSetVolume(muscle: $0.key, sets: $0.value) }
            .sorted {
                $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.rawValue < $1.muscle.rawValue
            }

        return AthleteContext(lifts: Array(ranked.prefix(maxLifts)).map(\.digest),
                              weeklySetsPerMuscle: weekly)
    }

    // MARK: - Rendering

    /// The history section for the framing prompt, or "" when there's no history or no
    /// budget. Drops the least-relevant lifts until the section fits `maxTokens`.
    func promptSection(maxTokens: Int) -> String {
        guard !isEmpty, maxTokens > 0 else { return "" }
        let header = """
        RECENT LOGGED TRAINING (real data — ground your loads, reps and exercise choices in it; \
        progress lifts trending up, hold or vary lifts that stall or regress):
        """
        let volumeLine: String = weeklySetsPerMuscle.isEmpty ? "" :
            "Working sets in the last 7 days: " +
            weeklySetsPerMuscle.map { "\($0.muscle.displayName) \($0.sets)" }.joined(separator: ", ") + "."

        var included = lifts
        while !included.isEmpty {
            let body = included.map { "• " + $0.promptLine }.joined(separator: "\n")
            let section = [header, body, volumeLine].filter { !$0.isEmpty }.joined(separator: "\n")
            if PromptBudget.estimatedTokens(section) <= maxTokens { return section }
            included.removeLast()
        }
        return ""
    }
}
