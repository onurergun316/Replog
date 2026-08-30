//
//  CoachInsightDetail.swift
//  Replog
//
//  One recorded coach insight, opened up.
//
//  The Profile feed shows a headline and a clamped line or two of reasoning. Everything
//  else the coach wrote down — the numbers it reasoned from, which lifts it was talking
//  about, what it decided to do — sits in the log's payload and was never readable. This
//  turns that payload into something a person can read.
//
//  Pure, and deliberately not given a `CoachingLog`: the store's model is `@Model`, and a
//  formatter that needs a container to be exercised is a formatter that stops being tested.
//  `CoachingLog.detail(units:catalog:)` is the thin bridge.
//
//  Two things it is careful about. Metrics arrive in a dictionary, so they are emitted in a
//  fixed order — a sheet whose rows shuffle between openings reads as a bug. And tags are a
//  mixed bag by design (catalog ids, the insight's own kind, a stall's chosen response), so
//  each is resolved to what it actually is rather than printed raw: "Seated_Dumbbell_Curl"
//  is not a label.
//

import Foundation

struct CoachInsightDetail: Equatable, Sendable {

    /// One numeric fact behind the insight, ready to render.
    struct Fact: Equatable, Sendable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    var kind: CoachInsightKind
    var title: String
    var body: String
    var date: Date
    /// The lifts this insight is about, by display name.
    var exercises: [String]
    /// The numbers behind it, in a stable order.
    var facts: [Fact]
    /// What the coach decided, from the tags that are neither a kind nor an exercise.
    var notes: [String]

    /// Whether there is anything beyond the headline and its reason worth a section.
    var hasSupportingDetail: Bool { !exercises.isEmpty || !facts.isEmpty || !notes.isEmpty }

    /// Builds a detail from the flat pieces a coaching log stores.
    ///
    /// `name` resolves a catalog id to a display name and returns nil for anything that is
    /// not one, which is what separates an exercise tag from a plain label.
    static func make(kind: CoachInsightKind, title: String, body: String, date: Date,
                     exId: String?, payload: CoachingPayload, units: Units,
                     name: (String) -> String?) -> CoachInsightDetail {
        var exercises: [String] = []
        var notes: [String] = []

        if let exId, let label = liftName(exId, name) {
            exercises.append(label)
        }
        for tag in payload.tags {
            // The kind is already the sheet's heading; repeating it as a chip says nothing.
            if CoachInsightKind(rawValue: tag) != nil { continue }
            if let resolved = name(tag) {
                if !exercises.contains(resolved) { exercises.append(resolved) }
            } else if !isDeletedCustomId(tag) {
                let note = readable(tag)
                if !notes.contains(note) { notes.append(note) }
            }
        }

        return CoachInsightDetail(
            kind: kind, title: title, body: body, date: date,
            exercises: exercises, facts: facts(from: payload.metrics, units: units), notes: notes)
    }

    /// What to call a catalog id: its real name, its token prettified, or nothing at all.
    ///
    /// Deleting a custom exercise deliberately leaves finished history alone — it is a
    /// factual record of training that happened — so a recorded insight can outlive the
    /// exercise it was about. Prettifying `custom-1f2e3d4c-…` produces
    /// "Custom-1f2e3d4c-…", which is not a lift name and is worth less than an empty row.
    private static func liftName(_ id: String, _ name: (String) -> String?) -> String? {
        if let resolved = name(id) { return resolved }
        return isDeletedCustomId(id) ? nil : readable(id)
    }

    /// A custom exercise's id, in the `custom-<uuid>` form `CustomExercise` mints.
    private static func isDeletedCustomId(_ token: String) -> Bool {
        token.hasPrefix("custom-")
    }

    // MARK: - Metrics

    /// The metrics this app actually writes, in the order they should be read: what happened,
    /// then how long it has been happening, then the numbers it happened at.
    private static let order = [
        "prCount", "totalVolumeKg", "workoutStreak", "programWeeks",
        "sessionsStalled", "patternDays", "lastE1RM", "lastTopWeightKg", "lastTopReps",
        "deloadToKg", "weeklyRateKg",
    ]

    static func facts(from metrics: [String: Double], units: Units) -> [Fact] {
        // Known keys in their documented order, then anything else alphabetically, so the
        // sheet is stable no matter what order the dictionary hands them over in.
        let known = order.filter { metrics[$0] != nil }
        let unknown = metrics.keys.filter { !order.contains($0) }.sorted()
        return (known + unknown).compactMap { key in
            guard let value = metrics[key] else { return nil }
            return Fact(label: label(for: key), value: format(key, value, units: units))
        }
    }

    private static func label(for key: String) -> String {
        switch key {
        case "prCount":         return "Personal bests"
        case "totalVolumeKg":   return "Session volume"
        case "workoutStreak":   return "Workout streak"
        case "programWeeks":    return "On this plan"
        case "sessionsStalled": return "Sessions stalled"
        case "patternDays":     return "Days in the pattern"
        case "lastE1RM":        return "Last estimated 1RM"
        case "lastTopWeightKg": return "Last top set"
        case "lastTopReps":     return "Last top reps"
        case "deloadToKg":      return "Deload to"
        case "weeklyRateKg":    return "Weekly change"
        default:                return readable(key)
        }
    }

    private static func format(_ key: String, _ value: Double, units: Units) -> String {
        switch key {
        case "totalVolumeKg", "lastE1RM", "lastTopWeightKg", "deloadToKg":
            return Formulas.formatWeight(kg: value, units: units)
        case "weeklyRateKg":
            // A rate reads as a direction first: "+0.4 kg" says something "0.4 kg" does not.
            let sign = value > 0 ? "+" : (value < 0 ? "−" : "")
            return sign + Formulas.formatBodyweight(kg: abs(value), units: units)
        case "workoutStreak", "patternDays":
            return count(value, "day")
        case "programWeeks":
            return count(value, "week")
        case "sessionsStalled":
            return count(value, "session")
        case "lastTopReps":
            return count(value, "rep")
        default:
            return number(value)
        }
    }

    private static func count(_ value: Double, _ noun: String) -> String {
        let whole = Int(value.rounded())
        return "\(whole) \(noun)\(whole == 1 ? "" : "s")"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// A stored token turned into something readable: `"deload"` → `"Deload"`,
    /// `"swapExercise"` → `"Swap Exercise"`, `"Seated_Dumbbell_Curl"` → `"Seated Dumbbell Curl"`.
    /// Used for tags, and for any metric key added after this file was written.
    static func readable(_ token: String) -> String {
        var spaced = ""
        for character in token.replacingOccurrences(of: "_", with: " ") {
            if character.isUppercase, !spaced.isEmpty, spaced.last != " " { spaced.append(" ") }
            spaced.append(character)
        }
        let trimmed = spaced.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}

extension CoachingLog {
    /// This recorded insight read as a `CoachInsightDetail`. Catalog ids — in `exId` and in
    /// the payload's tags — are resolved to exercise names on the way through.
    func detail(units: Units, catalog: ExerciseCatalog = .shared) -> CoachInsightDetail {
        CoachInsightDetail.make(kind: insightKind, title: summary, body: bodyMarkdown ?? "",
                                date: date, exId: exId, payload: payload, units: units,
                                name: { catalog.exercise(id: $0)?.name })
    }
}
