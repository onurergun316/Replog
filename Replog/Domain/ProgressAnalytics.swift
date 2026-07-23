//
//  ProgressAnalytics.swift
//  Replog
//
//  The Progress dashboard's derivations over stored history: weekly volume buckets,
//  muscle-group volume shares, rep-range mix, schedule adherence, PR events, and
//  relative strength. Everything is pure and calendar-injected; the catalog dependency
//  (exId → muscles) comes in as a closure so this stays testable without the bundle.
//

import Foundation

/// One Sunday-anchored week of training totals (oldest → newest in results).
struct WeekBucket: Equatable, Identifiable {
    var weekStart: Date
    var volumeKg: Double = 0
    var sets: Int = 0
    /// Distinct days trained that week.
    var workouts: Int = 0
    var id: Date { weekStart }
}

/// One muscle's share of attributed training volume within a window.
struct MuscleShare: Equatable, Identifiable {
    var muscle: Muscle
    var volumeKg: Double
    /// 0…1 of the total attributed volume (sums to 1 across the returned shares).
    var share: Double
    var id: Muscle { muscle }
}

/// Sets by rep range — the strength / hypertrophy / endurance mix.
struct RepRangeMix: Equatable {
    var strength = 0      // 1–5 reps
    var hypertrophy = 0   // 6–12 reps
    var endurance = 0     // 13+ reps
    var total: Int { strength + hypertrophy + endurance }
}

/// One week's schedule adherence: how many scheduled days were actually trained.
struct AdherenceWeek: Equatable, Identifiable {
    var weekStart: Date
    var scheduled: Int
    var done: Int
    var id: Date { weekStart }
}

/// A session that beat the exercise's previous all-time best e1RM.
struct PREvent: Equatable, Identifiable {
    var exId: String
    var date: Date
    var e1rm: Int
    var id: String { "\(exId)-\(date.timeIntervalSince1970)" }
}

enum ProgressAnalytics {

    /// The last `weeks` Sunday-anchored weeks (oldest → newest, empty weeks included),
    /// with volume, set count, and distinct training days per week.
    ///
    /// `load` decides what each set was worth; the default reads the stored weight, so a
    /// caller that hasn't opted in sees exactly the numbers it always did.
    static func weekBuckets(history: [HistoryEntry], weeks: Int,
                            load: LoadResolver = .stored,
                            today: Date = Date(),
                            calendar: Calendar = .current) -> [WeekBucket] {
        guard weeks > 0,
              let thisWeek = StreakEngine.startOfWeek(for: today, calendar: calendar) else { return [] }
        var buckets: [Date: WeekBucket] = [:]
        var starts: [Date] = []
        for offset in stride(from: -(weeks - 1), through: 0, by: 1) {
            guard let start = calendar.date(byAdding: .day, value: offset * 7, to: thisWeek) else { continue }
            buckets[start] = WeekBucket(weekStart: start)
            starts.append(start)
        }
        var daysPerWeek: [Date: Set<Date>] = [:]
        for entry in history {
            guard let week = StreakEngine.startOfWeek(for: entry.date, calendar: calendar),
                  var bucket = buckets[week] else { continue }
            for set in entry.sets {
                bucket.volumeKg += load.volumeKg(exId: entry.exId, set: set, on: entry.date)
                bucket.sets += 1
            }
            buckets[week] = bucket
            daysPerWeek[week, default: []].insert(calendar.startOfDay(for: entry.date))
        }
        return starts.map { start in
            var bucket = buckets[start] ?? WeekBucket(weekStart: start)
            bucket.workouts = daysPerWeek[start]?.count ?? 0
            return bucket
        }
    }

    /// Drops the run of empty weeks at the *start* of a series, so a first training week
    /// reads at the chart's left edge instead of stranded at the far right.
    ///
    /// `weekBuckets` zero-fills a fixed trailing window ending at the current week, and
    /// Swift Charts takes its x-domain from whatever it is handed — so a new athlete's
    /// only bar sat in the last twelfth of a 12-week chart, or the last 1% of an "All"
    /// one, preceded by empty space from before they had started training.
    ///
    /// Interior and trailing gaps are kept: a week you skipped is information, and the
    /// current week must stay the right edge. Keyed on `sets`, not `volumeKg` — a week of
    /// nothing but bodyweight work is zero kilograms under the default resolver, and it
    /// would be a lie to call that untrained.
    static func trimmingLeadingEmptyWeeks(_ buckets: [WeekBucket]) -> [WeekBucket] {
        guard let first = buckets.firstIndex(where: { $0.sets > 0 }) else { return buckets }
        return Array(buckets[first...])
    }

    /// Volume attributed to each primary muscle over the last `days` days, largest first.
    /// A set's full volume goes to every primary muscle of its exercise; shares are
    /// normalized over the attributed total so they always sum to 1.
    static func muscleShares(history: [HistoryEntry], days: Int,
                             muscles: (String) -> [Muscle],
                             load: LoadResolver = .stored,
                             today: Date = Date(),
                             calendar: Calendar = .current) -> [MuscleShare] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return [] }
        var volume: [Muscle: Double] = [:]
        for entry in history where entry.date >= cutoff {
            let targets = muscles(entry.exId)
            guard !targets.isEmpty else { continue }
            let entryVolume = load.volumeKg(entry)
            for muscle in targets { volume[muscle, default: 0] += entryVolume }
        }
        let total = volume.values.reduce(0, +)
        guard total > 0 else { return [] }
        return volume
            .map { MuscleShare(muscle: $0.key, volumeKg: $0.value, share: $0.value / total) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Sets by rep range over the last `days` days.
    ///
    /// Timed holds are excluded: their stored "reps" are seconds, so a 45-second plank
    /// would otherwise land in the endurance bucket as a set of 45.
    static func repRangeMix(history: [HistoryEntry], days: Int,
                            load: LoadResolver = .stored,
                            today: Date = Date(),
                            calendar: Calendar = .current) -> RepRangeMix {
        var mix = RepRangeMix()
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return mix }
        for entry in history where entry.date >= cutoff {
            guard !load.isTimedHold(exId: entry.exId) else { continue }
            for set in entry.sets {
                switch set.r {
                case ..<6: mix.strength += 1
                case 6...12: mix.hypertrophy += 1
                default: mix.endurance += 1
                }
            }
        }
        return mix
    }

    /// The last `weeks` weeks of schedule adherence (oldest → newest). Only *elapsed*
    /// scheduled days count in the current week, so today's still-due workout doesn't
    /// read as a miss.
    ///
    /// `since` drops the weeks before the athlete's first activity. Without it a brand-new
    /// account reads as months of missed sessions against a schedule it didn't have yet —
    /// an adherence percentage in the single digits on day three.
    static func adherence(scheduledDays: Set<Weekday>, doneDates: [Date], weeks: Int,
                          since firstActivity: Date? = nil,
                          today: Date = Date(),
                          calendar: Calendar = .current) -> [AdherenceWeek] {
        guard weeks > 0, !scheduledDays.isEmpty,
              let thisWeek = StreakEngine.startOfWeek(for: today, calendar: calendar) else { return [] }
        let done = Set(doneDates.map { calendar.startOfDay(for: $0) })
        let startOfToday = calendar.startOfDay(for: today)
        let firstWeek = firstActivity.flatMap { StreakEngine.startOfWeek(for: $0, calendar: calendar) }
        return stride(from: -(weeks - 1), through: 0, by: 1).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .day, value: offset * 7, to: thisWeek)
            else { return nil }
            if let firstWeek, weekStart < firstWeek { return nil }
            var scheduled = 0, doneCount = 0
            for day in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: day, to: weekStart),
                      date <= startOfToday,
                      scheduledDays.contains(Weekday.from(date, calendar: calendar)) else { continue }
                scheduled += 1
                if done.contains(date) { doneCount += 1 }
            }
            return AdherenceWeek(weekStart: weekStart, scheduled: scheduled, done: doneCount)
        }
    }

    /// Every session that beat its exercise's previous all-time best e1RM, newest first.
    /// The first-ever session of an exercise is a baseline, not a PR.
    ///
    /// Scored over *effective* load, so a rep gained on a bodyweight movement can be a
    /// personal record — under the stored e1RM every such session scored zero and no
    /// calisthenics PR could ever be detected.
    static func prEvents(history: [HistoryEntry], load: LoadResolver = .stored) -> [PREvent] {
        var events: [PREvent] = []
        let byExercise = Dictionary(grouping: history, by: \.exId)
        for (exId, entries) in byExercise {
            var best = Int.min
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                let e1rm = load.e1rm(entry)
                if best != Int.min, e1rm > best {
                    events.append(PREvent(exId: exId, date: entry.date, e1rm: e1rm))
                }
                best = max(best, e1rm)
            }
        }
        return events.sorted { $0.date > $1.date }
    }

    /// One finished workout: every exercise written by a single Finish.
    ///
    /// `SessionFinisher` stamps one `sessionId` and one exact timestamp across the whole
    /// batch, so a session is recoverable even for history written before the id existed
    /// (those group by timestamp alone). This is what makes "total weight lifted per
    /// session" answerable at all — history is otherwise per-exercise-per-day, and two
    /// workouts in one day used to merge into one.
    struct SessionGroup: Identifiable {
        var date: Date
        var entries: [HistoryEntry]
        /// Captured at finish; nil for history written before attribution existed.
        var workoutName: String?
        var planName: String?
        var durationSeconds: Int?
        var id: Date { date }

        var setCount: Int { entries.reduce(0) { $0 + $1.sets.count } }
    }

    /// Every finished session, oldest → newest.
    static func sessions(history: [HistoryEntry]) -> [SessionGroup] {
        let grouped = Dictionary(grouping: history) { entry in
            entry.sessionId.map { AnyHashable($0) } ?? AnyHashable(entry.date)
        }
        return grouped.values.compactMap { entries -> SessionGroup? in
            guard let first = entries.min(by: { $0.date < $1.date }) else { return nil }
            return SessionGroup(date: first.date, entries: entries,
                                workoutName: first.workoutName, planName: first.planName,
                                durationSeconds: first.durationSeconds)
        }
        .sorted { $0.date < $1.date }
    }

    /// A session's total tonnage.
    static func tonnage(of session: SessionGroup, load: LoadResolver = .stored) -> Double {
        session.entries.reduce(0.0) { $0 + load.volumeKg($1) }
    }

    /// Tonnage grouped by the plan each session belonged to, largest first. Sessions
    /// finished before attribution existed group under `nil`.
    static func tonnageByPlan(history: [HistoryEntry],
                              load: LoadResolver = .stored) -> [(plan: String?, volumeKg: Double)] {
        var totals: [String?: Double] = [:]
        for session in sessions(history: history) {
            totals[session.planName, default: 0] += tonnage(of: session, load: load)
        }
        return totals.map { (plan: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Tonnage grouped by workout template, largest first.
    static func tonnageByWorkout(history: [HistoryEntry],
                                 load: LoadResolver = .stored) -> [(workout: String?, volumeKg: Double)] {
        var totals: [String?: Double] = [:]
        for session in sessions(history: history) {
            totals[session.workoutName, default: 0] += tonnage(of: session, load: load)
        }
        return totals.map { (workout: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// How the window's tonnage splits between external load and the athlete's own body.
    static func loadSplit(history: [HistoryEntry], days: Int,
                          load: LoadResolver = .stored,
                          today: Date = Date(),
                          calendar: Calendar = .current) -> (externalKg: Double, bodyweightKg: Double) {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return (0, 0) }
        var external = 0.0, bodyweight = 0.0
        for entry in history where entry.date >= cutoff {
            external += load.externalVolumeKg(entry)
            bodyweight += load.bodyweightVolumeKg(entry)
        }
        return (external, bodyweight)
    }

    /// The athlete's first day of training: the earlier of their first logged set and
    /// their first completed day. `nil` before they have trained at all. Charts clamp
    /// their x-domain to this so nothing is drawn from before they started.
    static func firstActivity(history: [HistoryEntry], doneDates: [Date]) -> Date? {
        let dates = history.map(\.date) + doneDates
        return dates.min()
    }

    /// Estimated 1RM as a multiple of bodyweight — the classic strength-standard read.
    static func relativeStrength(e1rm: Int, bodyweightKg: Double?) -> Double? {
        guard let bodyweightKg, bodyweightKg > 0 else { return nil }
        return Double(e1rm) / bodyweightKg
    }
}
