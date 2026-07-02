//
//  Coaching.swift
//  Replog
//
//  The trainer's durable memory. A `CoachingLog` is a dated, typed note the on-device
//  coach writes to itself — a progression recommendation, a detected plateau, a
//  bodyweight check-in, a published report — so it can "remember" context across weeks
//  and feed later reasoning (progression engine, weekly/monthly reports).
//
//  Like `HistoryEntry`, a log is a flat, queryable record: it references the catalog by
//  `exId` and a plan by `planId` (UUIDs, not relationships — matching `ActiveSession.workoutId`),
//  so the memory OUTLIVES the plan or exercise it once concerned. Structured detail rides
//  in a JSON payload, decoded on demand (the `HistoryEntry.sets` pattern).
//

import Foundation
import SwiftData

/// What a `CoachingLog` records. Drives filtering, iconography, and report grouping.
enum CoachingKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A free-form coaching note.
    case note
    /// A load/rep recommendation for a specific lift (from the progression engine).
    case progression
    /// A detected stall across sessions.
    case plateau
    /// A recommended deload / back-off week.
    case deload
    /// A bodyweight check-in observation.
    case bodyweight
    /// A published weekly summary.
    case weeklyReport
    /// A published monthly rollup.
    case monthlyReport
    /// The coach adjusted the plan (split/volume/exercise choice).
    case planAdjustment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .note:          return "Note"
        case .progression:   return "Progression"
        case .plateau:       return "Plateau"
        case .deload:        return "Deload"
        case .bodyweight:    return "Bodyweight"
        case .weeklyReport:  return "Weekly report"
        case .monthlyReport: return "Monthly report"
        case .planAdjustment: return "Plan adjustment"
        }
    }
}

/// Structured detail for a `CoachingLog`, kept flexible so each `CoachingKind` can carry
/// only what it needs. Numeric facts (weights, e1RM, trend %, bodyweight) go in `metrics`;
/// short labels (recommended action verbs, muscle names) go in `tags`.
struct CoachingPayload: Codable, Hashable, Sendable {
    /// Named numeric facts, e.g. `["fromWeightKg": 60, "toWeightKg": 62.5, "trendPct": 4.1]`.
    var metrics: [String: Double]
    /// Short labels, e.g. `["increaseLoad"]` or `["chest", "triceps"]`.
    var tags: [String]

    init(metrics: [String: Double] = [:], tags: [String] = []) {
        self.metrics = metrics
        self.tags = tags
    }

    /// Lenient decoding so a bare `{}` (the model's default `payloadJSON`) and forward-compatible
    /// payloads that omit a field decode to sensible empties instead of throwing.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.metrics = try c.decodeIfPresent([String: Double].self, forKey: .metrics) ?? [:]
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Convenience metric accessor (nil when absent).
    subscript(metric key: String) -> Double? { metrics[key] }
}

@Model
final class CoachingLog {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Stored as `CoachingKind.rawValue`; use `kind` for typed access.
    var kindRaw: String = CoachingKind.note.rawValue
    /// Human-readable one-liner (rendered in reports / a future coaching feed).
    var summary: String = ""
    /// The exercise this log concerns (`Exercise.id` in the static catalog), if any.
    var exId: String?
    /// The plan this log concerns, if any. A plain id reference (not a relationship) so the
    /// memory survives the plan's deletion.
    var planId: UUID?
    /// JSON-encoded `CoachingPayload` of structured detail.
    var payloadJSON: String = "{}"

    init(
        kind: CoachingKind,
        summary: String,
        date: Date = Date(),
        exId: String? = nil,
        planId: UUID? = nil,
        payload: CoachingPayload = CoachingPayload()
    ) {
        self.kindRaw = kind.rawValue
        self.summary = summary
        self.date = date
        self.exId = exId
        self.planId = planId
        self.payload = payload
    }

    var kind: CoachingKind {
        get { CoachingKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    /// Decoded structured payload.
    var payload: CoachingPayload {
        get { (try? JSONDecoder().decode(CoachingPayload.self, from: Data(payloadJSON.utf8))) ?? CoachingPayload() }
        set { payloadJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}" }
    }
}
