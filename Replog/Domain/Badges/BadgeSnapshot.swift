//
//  BadgeSnapshot.swift
//  Replog
//
//  Everything the badge engine is allowed to reason about, in one value type.
//
//  The snapshot is built once from the store and then the engine is pure over it, which is
//  what makes fifty-odd unlock rules testable without a database. It is also the contract
//  that keeps the badge list honest: if a fact is not in here, no badge may depend on it.
//

import Foundation

/// One finished session, distilled to what a badge might ask about.
nonisolated struct BadgeSession: Equatable, Sendable {
    /// When the session *started*. `SessionFinisher` logs history against the start time,
    /// so a workout begun at 23:00 and finished after midnight belongs to the 23:00 day —
    /// which is also what makes an early-bird or night-owl badge meaningful.
    var date: Date
    var exerciseIds: [String]
    var tonnageKg: Double
    var setCount: Int
    var repCount: Int
    var durationSeconds: Int?
    /// Lifts in this session that beat their own previous best estimated 1RM.
    var personalBests: Int
    /// Rep ranges touched: low is 1 to 5, middle 6 to 12, high 13 and up.
    var hitLowReps: Bool
    var hitMidReps: Bool
    var hitHighReps: Bool

    init(date: Date, exerciseIds: [String] = [], tonnageKg: Double = 0,
         setCount: Int = 0, repCount: Int = 0, durationSeconds: Int? = nil,
         personalBests: Int = 0,
         hitLowReps: Bool = false, hitMidReps: Bool = false, hitHighReps: Bool = false) {
        self.date = date
        self.exerciseIds = exerciseIds
        self.tonnageKg = tonnageKg
        self.setCount = setCount
        self.repCount = repCount
        self.durationSeconds = durationSeconds
        self.personalBests = personalBests
        self.hitLowReps = hitLowReps
        self.hitMidReps = hitMidReps
        self.hitHighReps = hitHighReps
    }

    var coversEveryRepRange: Bool { hitLowReps && hitMidReps && hitHighReps }
}

nonisolated struct BadgeSnapshot: Sendable {
    var now: Date = Date()
    var calendar: Calendar = .current

    // Consistency
    /// Fully completed workouts. A partial finish saves history but never counts.
    var totalWorkouts: Int = 0
    /// Calendar days with a completed workout, ascending.
    var doneDates: [Date] = []
    var dayStreak: Int = 0
    var weekStreak: Int = 0
    var perfectWeeks: Int = 0

    // Sessions, oldest first
    var sessions: [BadgeSession] = []

    // Strength
    var personalBestTotal: Int = 0
    /// Best estimated 1RM as a multiple of bodyweight, per movement pattern.
    var bestLowerRatio: Double = 0
    var bestPushRatio: Double = 0
    var bestPullRatio: Double = 0

    // Volume
    var tonnageKg: Double = 0
    var setTotal: Int = 0
    var repTotal: Int = 0
    var pushTonnageKg: Double = 0
    var pullTonnageKg: Double = 0

    // Breadth
    var distinctExercises: Int = 0
    var distinctMuscles: Int = 0
    var distinctEquipment: Int = 0
    var distinctCategories: Int = 0
    var distinctCompounds: Int = 0

    // Habits
    var bodyweightCheckIns: Int = 0
    var readinessCheckIns: Int = 0
    var customExercises: Int = 0
    var plansBuilt: Int = 0
    /// The longest gap in days that was followed by another completed workout.
    var longestReturnGapDays: Int = 0
    /// The longest a movement lay untouched before it set a new best.
    var longestDormantBestDays: Int = 0

    // MARK: - Derived

    /// Distinct calendar months containing a completed workout.
    var monthsActive: Int {
        Set(doneDates.map { date -> DateComponents in
            calendar.dateComponents([.year, .month], from: date)
        }).count
    }

    /// Weekday numbers (1 = Sunday) that have ever been trained.
    var weekdaysTrained: Set<Int> {
        Set(doneDates.map { calendar.component(.weekday, from: $0) })
    }

    var bestSessionTonnageKg: Double { sessions.map(\.tonnageKg).max() ?? 0 }
    var bestSessionMinutes: Int { (sessions.compactMap(\.durationSeconds).max() ?? 0) / 60 }
    var bestPersonalBestsInOneSession: Int { sessions.map(\.personalBests).max() ?? 0 }
    var hasRepRangeSweep: Bool { sessions.contains { $0.coversEveryRepRange } }

    func sessions(startedBefore hour: Int) -> Int {
        sessions.filter { calendar.component(.hour, from: $0.date) < hour }.count
    }

    func sessions(startedAtOrAfter hour: Int) -> Int {
        sessions.filter { calendar.component(.hour, from: $0.date) >= hour }.count
    }

    var weekendSessions: Int {
        sessions.filter { calendar.isDateInWeekend($0.date) }.count
    }

    /// Sessions completed within `days` of the very first one, inclusive of the first.
    func sessionsInFirst(days: Int) -> Int {
        guard let first = doneDates.min(),
              let cutoff = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: first)) else {
            return 0
        }
        return doneDates.filter { $0 < cutoff }.count
    }

    /// How far apart push and pull tonnage sit, as a percentage of the larger.
    /// 0 is perfectly even. Meaningless with nothing logged, so nil then.
    var pushPullSpreadPercent: Double? {
        let high = max(pushTonnageKg, pullTonnageKg)
        guard high > 0 else { return nil }
        return abs(pushTonnageKg - pullTonnageKg) / high * 100
    }

    func bestRatio(for pattern: StrengthPattern) -> Double {
        switch pattern {
        case .lowerCompound: return bestLowerRatio
        case .upperPush:     return bestPushRatio
        case .upperPull:     return bestPullRatio
        case .isolation:     return 0   // no meaningful bodyweight standard
        }
    }
}
