//
//  History.swift
//  Replog
//
//  Per-exercise progression history, appended on Finish. Drives Progress charts,
//  trend %, and the "previous" reference for the next session's logging.
//

import Foundation
import SwiftData

/// One recorded set (weight x reps) within a history entry.
struct RecordedSet: Codable, Hashable, Sendable {
    var w: Double
    var r: Int
}

@Model
final class HistoryEntry {
    var id: UUID = UUID()
    /// References `Exercise.id` in the static catalog.
    var exId: String = ""
    var date: Date = Date()
    var topW: Double = 0
    var topR: Int = 0
    var e1rm: Int = 0
    /// The RPE logged on the top set — lets `LoadCalibrator` infer the true working load and
    /// correct a starting estimate. Defaults to 8 for entries written before this existed.
    var topRPE: Int = 8
    /// JSON-encoded `[RecordedSet]` of every set done that day (for the Session Log).
    var setsJSON: String = "[]"

    // MARK: Session attribution
    //
    // The live session knows which workout and plan it came from and when it started,
    // and all of that used to be destroyed when the session was deleted on finish —
    // leaving history as a flat per-exercise-per-day trail. Stamping it here is what
    // makes "tonnage by plan / by workout" and session duration derivable at all.
    // Optional throughout: rows written before this existed simply have none, and no
    // backfill is possible.

    /// Groups the entries written by one finish. Sessions are also reconstructible from
    /// the shared exact timestamp; this makes it explicit rather than incidental.
    var sessionId: UUID?
    /// The `Workout` this session was built from, if it still exists.
    var workoutId: UUID?
    /// Names captured at finish time, so a later rename or deletion can't orphan history.
    var workoutName: String?
    var planName: String?
    /// Wall-clock length of the session, in seconds.
    var durationSeconds: Int?

    init(exId: String, date: Date, topW: Double, topR: Int, e1rm: Int, sets: [RecordedSet],
         topRPE: Int = 8, sessionId: UUID? = nil, workoutId: UUID? = nil,
         workoutName: String? = nil, planName: String? = nil, durationSeconds: Int? = nil) {
        self.exId = exId
        self.date = date
        self.topW = topW
        self.topR = topR
        self.e1rm = e1rm
        self.topRPE = topRPE
        self.sets = sets
        self.sessionId = sessionId
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.planName = planName
        self.durationSeconds = durationSeconds
    }

    /// Decoded sets done that day.
    var sets: [RecordedSet] {
        get { (try? JSONDecoder().decode([RecordedSet].self, from: Data(setsJSON.utf8))) ?? [] }
        set { setsJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    }
}
