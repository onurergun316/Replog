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

/// Everything one exercise contributed inside a window.
///
/// The Volume screen's headline numbers are all sums over this: total tonnage, sets, the
/// external/bodyweight split, the rep-range mix. Deriving them once, per exercise, is
/// what lets every one of those figures open into "and here is what it was made of"
/// without four more passes over history.
struct ExerciseContribution: Equatable, Identifiable {
    var exId: String
    var volumeKg: Double = 0
    /// Plates, dumbbells, a dip belt.
    var externalKg: Double = 0
    /// The part that was the athlete's own body.
    var bodyweightKg: Double = 0
    var sets: Int = 0
    /// Total reps logged (seconds, for a timed hold).
    var reps: Int = 0
    /// The heaviest single set's estimated 1RM over effective load.
    var bestE1rm: Int = 0
    /// Sets by rep range. Timed holds are excluded, exactly as in `repRangeMix`.
    var mix = RepRangeMix()
    /// Start-of-day for every day this exercise was trained, newest first.
    var days: [Date] = []

    var id: String { exId }
    var sessionCount: Int { days.count }
    var lastTrained: Date? { days.first }
    /// True when any of the load came from moving the athlete's own body.
    var isBodyweight: Bool { bodyweightKg > 0 }
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

    /// Hard sets per primary muscle over the last `days` days, most-trained first.
    ///
    /// Sets, not kilograms. Tonnage makes a leg-press day look heroic and a strict
    /// overhead-press day look like nothing, so it is the wrong unit for asking whether
    /// training is balanced — every app that does this well counts sets. Tonnage stays
    /// the Volume headline, where it is a fair celebration number.
    ///
    /// A count is also honest on session one, where a *share* is not: "chest 38%" from
    /// three sessions swings wildly and reads as precision the data doesn't have.
    static func muscleSets(history: [HistoryEntry], days: Int,
                           muscles: (String) -> [Muscle],
                           today: Date = Date(),
                           calendar: Calendar = .current) -> [(muscle: Muscle, sets: Int)] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return [] }
        var counts: [Muscle: Int] = [:]
        for entry in history where entry.date >= cutoff {
            let targets = muscles(entry.exId)
            guard !targets.isEmpty else { continue }
            for muscle in targets { counts[muscle, default: 0] += entry.sets.count }
        }
        return counts.map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets == $1.sets ? $0.muscle.displayName < $1.muscle.displayName
                                         : $0.sets > $1.sets }
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

        /// What to call this session on screen — its workout's real name ("Day 2"),
        /// never a generic label while the store still knows one.
        ///
        /// The plan is the second-best answer and only reached when the workout itself
        /// can't be named: a session finished before attribution existed whose exercises
        /// no longer match any workout closely enough for `SessionAttributionBackfill`
        /// to claim one. `fallback` is the caller's last resort for that case.
        func title(fallback: String = "Workout") -> String {
            workoutName ?? planName ?? fallback
        }
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

    /// What every exercise contributed over the last `days` days, heaviest first.
    ///
    /// One pass, so the Volume screen's four summaries all break down into the same
    /// rows and can never disagree with each other about a total.
    static func exerciseContributions(history: [HistoryEntry], days: Int,
                                      load: LoadResolver = .stored,
                                      today: Date = Date(),
                                      calendar: Calendar = .current) -> [ExerciseContribution] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return [] }
        var byExercise: [String: ExerciseContribution] = [:]
        var daysSeen: [String: Set<Date>] = [:]
        for entry in history.sorted(by: { $0.date < $1.date }) where entry.date >= cutoff {
            var row = byExercise[entry.exId] ?? ExerciseContribution(exId: entry.exId)
            let isHold = load.isTimedHold(exId: entry.exId)
            for set in entry.sets {
                let reps = load.repEquivalents(exId: entry.exId, set: set)
                row.volumeKg += load.volumeKg(exId: entry.exId, set: set, on: entry.date)
                row.externalKg += set.w * reps
                row.sets += 1
                row.reps += set.r
                // Timed holds store seconds in `r`, so a 45-second plank would otherwise
                // land in the endurance bucket as a set of 45 (see `repRangeMix`).
                if !isHold {
                    switch set.r {
                    case ..<6: row.mix.strength += 1
                    case 6...12: row.mix.hypertrophy += 1
                    default: row.mix.endurance += 1
                    }
                }
            }
            row.bestE1rm = Swift.max(row.bestE1rm, load.e1rm(entry))
            byExercise[entry.exId] = row
            daysSeen[entry.exId, default: []].insert(calendar.startOfDay(for: entry.date))
        }
        return byExercise.values.map { row in
            var row = row
            row.bodyweightKg = Swift.max(0, row.volumeKg - row.externalKg)
            row.days = (daysSeen[row.exId] ?? []).sorted(by: >)
            return row
        }
        .sorted { $0.volumeKg == $1.volumeKg ? $0.exId < $1.exId : $0.volumeKg > $1.volumeKg }
    }

    /// Contributions folded into groups — by muscle, by force, by whatever the caller
    /// can name — largest first. Rows whose key is `nil` are dropped, since an
    /// uncategorised slice of a part-to-whole chart is noise.
    static func grouped<Key: Hashable>(
        _ contributions: [ExerciseContribution],
        by key: (ExerciseContribution) -> Key?
    ) -> [(key: Key, volumeKg: Double, sets: Int, exercises: [ExerciseContribution])] {
        var groups: [Key: [ExerciseContribution]] = [:]
        var order: [Key] = []
        for row in contributions {
            guard let key = key(row) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        return order.map { key in
            let rows = groups[key] ?? []
            return (key: key,
                    volumeKg: rows.reduce(0) { $0 + $1.volumeKg },
                    sets: rows.reduce(0) { $0 + $1.sets },
                    exercises: rows)
        }
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

    /// One training day's external/bodyweight split, oldest → newest. Rest days are not
    /// emitted: a zero-height stacked bar is not a reading, it's a gap.
    static func dailyLoadSplit(history: [HistoryEntry], days: Int,
                               load: LoadResolver = .stored,
                               today: Date = Date(),
                               calendar: Calendar = .current)
    -> [(day: Date, externalKg: Double, bodyweightKg: Double)] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return [] }
        var totals: [Date: (external: Double, bodyweight: Double)] = [:]
        for entry in history where entry.date >= cutoff {
            let day = calendar.startOfDay(for: entry.date)
            var running = totals[day] ?? (0, 0)
            running.external += load.externalVolumeKg(entry)
            running.bodyweight += load.bodyweightVolumeKg(entry)
            totals[day] = running
        }
        return totals.keys.sorted().map {
            (day: $0, externalKg: totals[$0]?.external ?? 0, bodyweightKg: totals[$0]?.bodyweight ?? 0)
        }
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
