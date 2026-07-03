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

    init(exId: String, date: Date, topW: Double, topR: Int, e1rm: Int, sets: [RecordedSet], topRPE: Int = 8) {
        self.exId = exId
        self.date = date
        self.topW = topW
        self.topR = topR
        self.e1rm = e1rm
        self.topRPE = topRPE
        self.sets = sets
    }

    /// Decoded sets done that day.
    var sets: [RecordedSet] {
        get { (try? JSONDecoder().decode([RecordedSet].self, from: Data(setsJSON.utf8))) ?? [] }
        set { setsJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    }
}
