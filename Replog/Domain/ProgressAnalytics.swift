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
    static func weekBuckets(history: [HistoryEntry], weeks: Int,
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
                bucket.volumeKg += set.w * Double(set.r)
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

    /// Volume attributed to each primary muscle over the last `days` days, largest first.
    /// A set's full volume goes to every primary muscle of its exercise; shares are
    /// normalized over the attributed total so they always sum to 1.
    static func muscleShares(history: [HistoryEntry], days: Int,
                             muscles: (String) -> [Muscle],
                             today: Date = Date(),
                             calendar: Calendar = .current) -> [MuscleShare] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return [] }
        var volume: [Muscle: Double] = [:]
        for entry in history where entry.date >= cutoff {
            let targets = muscles(entry.exId)
            guard !targets.isEmpty else { continue }
            let entryVolume = entry.sets.reduce(0.0) { $0 + $1.w * Double($1.r) }
            for muscle in targets { volume[muscle, default: 0] += entryVolume }
        }
        let total = volume.values.reduce(0, +)
        guard total > 0 else { return [] }
        return volume
            .map { MuscleShare(muscle: $0.key, volumeKg: $0.value, share: $0.value / total) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Sets by rep range over the last `days` days.
    static func repRangeMix(history: [HistoryEntry], days: Int,
                            today: Date = Date(),
                            calendar: Calendar = .current) -> RepRangeMix {
        var mix = RepRangeMix()
        guard let cutoff = calendar.date(byAdding: .day, value: -days,
                                         to: calendar.startOfDay(for: today)) else { return mix }
        for entry in history where entry.date >= cutoff {
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
    static func adherence(scheduledDays: Set<Weekday>, doneDates: [Date], weeks: Int,
                          today: Date = Date(),
                          calendar: Calendar = .current) -> [AdherenceWeek] {
        guard weeks > 0, !scheduledDays.isEmpty,
              let thisWeek = StreakEngine.startOfWeek(for: today, calendar: calendar) else { return [] }
        let done = Set(doneDates.map { calendar.startOfDay(for: $0) })
        let startOfToday = calendar.startOfDay(for: today)
        return stride(from: -(weeks - 1), through: 0, by: 1).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .day, value: offset * 7, to: thisWeek)
            else { return nil }
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
    static func prEvents(history: [HistoryEntry]) -> [PREvent] {
        var events: [PREvent] = []
        let byExercise = Dictionary(grouping: history, by: \.exId)
        for (exId, entries) in byExercise {
            var best = Int.min
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                if best != Int.min, entry.e1rm > best {
                    events.append(PREvent(exId: exId, date: entry.date, e1rm: entry.e1rm))
                }
                best = max(best, entry.e1rm)
            }
        }
        return events.sorted { $0.date > $1.date }
    }

    /// Estimated 1RM as a multiple of bodyweight — the classic strength-standard read.
    static func relativeStrength(e1rm: Int, bodyweightKg: Double?) -> Double? {
        guard let bodyweightKg, bodyweightKg > 0 else { return nil }
        return Double(e1rm) / bodyweightKg
    }
}
