//
//  BadgeAwarding.swift
//  Replog
//
//  The glue between the store and the pure engine: build a snapshot of everything the
//  athlete has done, ask which badges that satisfies, and write down the new ones.
//
//  Runs after a finished session and once at launch. Running it at launch is what lets an
//  athlete who already has two years of training open the update and find their history
//  recognised, rather than an empty board that implies none of it counted.
//

import Foundation
import SwiftData

@MainActor
enum BadgeAwarding {

    // MARK: - Building the snapshot

    /// Everything the engine may reason about, gathered from the store.
    ///
    /// One pass over history, grouped into sessions. `HistoryEntry.date` is the session's
    /// *start*, so grouping by `sessionId` (falling back to the exact timestamp for rows
    /// written before that existed) reconstructs each workout as it happened.
    static func snapshot(context: ModelContext, catalog: ExerciseCatalog = .shared,
                         now: Date = Date(), calendar: Calendar = .current) -> BadgeSnapshot {
        let profile = context.userProfile()
        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let bodyweights = context.bodyweightEntries()
        let plans = context.allPlans()
        let load = LoadResolver.live(catalog: catalog, bodyweightEntries: bodyweights)

        var snapshot = BadgeSnapshot(now: now, calendar: calendar)
        snapshot.totalWorkouts = profile.totalWorkouts
        snapshot.doneDates = profile.doneDates.sorted()
        let scheduled = StreakEngine.scheduledDays(in: plans)
        snapshot.dayStreak = StreakEngine.workoutStreak(scheduledDays: scheduled,
                                                        doneDates: profile.doneDates, today: now)
        snapshot.weekStreak = StreakEngine.weekStreak(scheduledDays: scheduled,
                                                       doneDates: profile.doneDates, today: now)
        snapshot.perfectWeeks = perfectWeekCount(scheduledDays: scheduled,
                                                 doneDates: profile.doneDates,
                                                 now: now, calendar: calendar)
        snapshot.plansBuilt = plans.count
        snapshot.bodyweightCheckIns = bodyweights.count
        snapshot.readinessCheckIns = ((try? context.fetch(FetchDescriptor<ReadinessEntry>())) ?? []).count
        snapshot.customExercises = context.customExercises().count

        // Per-exercise bests, walked in date order so "beat your previous best" is judged
        // against what was known at the time rather than the final all-time best.
        var bestE1RM: [String: Int] = [:]
        var lastSeen: [String: Date] = [:]
        var personalBestTotal = 0
        var longestDormantBestDays = 0

        var exerciseIds = Set<String>()
        var muscles = Set<Muscle>()
        var equipment = Set<Equipment>()
        var categories = Set<ExerciseCategory>()
        var compounds = Set<String>()
        // The heaviest weigh-in ever recorded, so a relative-strength ratio can never be
        // inflated by having stepped on the scale light once.
        let heaviestBodyweight = bodyweights.map(\.weightKg).max() ?? 0

        // Group into sessions.
        var grouped: [AnyHashable: [HistoryEntry]] = [:]
        var order: [AnyHashable] = []
        for entry in history {
            let key: AnyHashable = entry.sessionId.map { AnyHashable($0) } ?? AnyHashable(entry.date)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(entry)
        }

        var sessions: [BadgeSession] = []
        for key in order {
            guard let entries = grouped[key], let first = entries.first else { continue }
            var session = BadgeSession(date: first.date)
            session.durationSeconds = entries.compactMap(\.durationSeconds).max()

            for entry in entries {
                exerciseIds.insert(entry.exId)
                let exercise = catalog.exercise(id: entry.exId)
                if let exercise {
                    muscles.formUnion(exercise.primaryMuscles)
                    if let kit = exercise.equipment { equipment.insert(kit) }
                    categories.insert(exercise.category)
                    if exercise.mechanic == .compound { compounds.insert(entry.exId) }
                }

                session.exerciseIds.append(entry.exId)
                for set in entry.sets {
                    session.setCount += 1
                    session.repCount += set.r
                    switch set.r {
                    case ...5:   session.hitLowReps = true
                    case 6...12: session.hitMidReps = true
                    default:     session.hitHighReps = true
                    }
                }
                let tonnage = entry.sets.reduce(0.0) { total, set in
                    total + load.volumeKg(exId: entry.exId,
                                          set: RecordedSet(w: set.w, r: set.r), on: entry.date)
                }
                session.tonnageKg += tonnage

                // Push/pull split, for the balance badge.
                switch exercise?.force {
                case .push?: snapshot.pushTonnageKg += tonnage
                case .pull?: snapshot.pullTonnageKg += tonnage
                default: break
                }

                // A best is only a best against what came before it.
                let e1rm = load.e1rm(entry)
                if let previous = bestE1RM[entry.exId] {
                    if e1rm > previous {
                        session.personalBests += 1
                        personalBestTotal += 1
                        if let seen = lastSeen[entry.exId] {
                            let gap = calendar.dateComponents([.day], from: seen, to: entry.date).day ?? 0
                            longestDormantBestDays = max(longestDormantBestDays, gap)
                        }
                    }
                } else if e1rm > 0 {
                    // The first time a lift is logged there is nothing to beat, so it is a
                    // baseline rather than a record. Counting it would hand out a "personal
                    // best" for every new movement ever tried.
                    bestE1RM[entry.exId] = e1rm
                }
                bestE1RM[entry.exId] = max(bestE1RM[entry.exId] ?? 0, e1rm)
                lastSeen[entry.exId] = entry.date

                // Relative strength, against the heaviest bodyweight ever recorded so the
                // ratio can never be inflated by having weighed in light once.
                if heaviestBodyweight > 0, let exercise {
                    let ratio = Double(e1rm) / heaviestBodyweight
                    switch StartingLoadEstimator.pattern(for: exercise) {
                    case .lowerCompound: snapshot.bestLowerRatio = max(snapshot.bestLowerRatio, ratio)
                    case .upperPush:     snapshot.bestPushRatio = max(snapshot.bestPushRatio, ratio)
                    case .upperPull:     snapshot.bestPullRatio = max(snapshot.bestPullRatio, ratio)
                    case .isolation:     break
                    }
                }
            }

            snapshot.tonnageKg += session.tonnageKg
            snapshot.setTotal += session.setCount
            snapshot.repTotal += session.repCount
            sessions.append(session)
        }

        snapshot.sessions = sessions
        snapshot.personalBestTotal = personalBestTotal
        snapshot.longestDormantBestDays = longestDormantBestDays
        snapshot.distinctExercises = exerciseIds.count
        snapshot.distinctMuscles = muscles.count
        snapshot.distinctEquipment = equipment.count
        snapshot.distinctCategories = categories.count
        snapshot.distinctCompounds = compounds.count
        snapshot.longestReturnGapDays = longestReturnGap(doneDates: snapshot.doneDates,
                                                          calendar: calendar)
        return snapshot
    }

    /// The longest break that was followed by another completed workout. A gap that is
    /// still open is not a comeback yet, which is why only gaps *between* days count.
    static func longestReturnGap(doneDates: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(doneDates.map { calendar.startOfDay(for: $0) }).sorted()
        guard days.count > 1 else { return 0 }
        var longest = 0
        for (previous, next) in zip(days, days.dropFirst()) {
            longest = max(longest, calendar.dateComponents([.day], from: previous, to: next).day ?? 0)
        }
        return longest
    }

    /// Weeks in which every scheduled day was trained, counted over the whole history.
    /// With no schedule at all a "perfect week" has no meaning, so nothing is awarded.
    static func perfectWeekCount(scheduledDays: Set<Weekday>, doneDates: [Date],
                                 now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !scheduledDays.isEmpty, let earliest = doneDates.min() else { return 0 }
        let doneDays = Set(doneDates.map { calendar.startOfDay(for: $0) })
        var count = 0
        var cursor = StreakCalendar.weekStart(today: earliest, calendar: calendar)
            ?? calendar.startOfDay(for: earliest)
        let end = calendar.startOfDay(for: now)

        while cursor <= end {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: cursor) }
            // A week still in progress cannot be judged complete yet.
            let finished = days.allSatisfy { $0 <= end }
            if finished {
                let satisfied = days.allSatisfy { day in
                    !scheduledDays.contains(Weekday.from(day, calendar: calendar)) || doneDays.contains(day)
                }
                if satisfied { count += 1 }
            }
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = nextWeek
        }
        return count
    }

    // MARK: - Awarding

    /// Awards every badge now earned that has not been awarded before, and returns them.
    ///
    /// Idempotent: an id already in the store is skipped, so this can run at launch and
    /// after every session without ever duplicating. The caller saves the context.
    @discardableResult
    static func award(context: ModelContext, catalog: ExerciseCatalog = .shared,
                      planName: String? = nil, workoutName: String? = nil,
                      now: Date = Date(), calendar: Calendar = .current) -> [Badge] {
        let snapshot = snapshot(context: context, catalog: catalog, now: now, calendar: calendar)
        let already = context.earnedBadgeIds()
        let newlyEarned = BadgeEngine.earned(in: snapshot).filter { !already.contains($0.id) }

        for badge in newlyEarned {
            let progress = BadgeEngine.progress(badge.criterion, in: snapshot)
            let award = BadgeAward(badgeId: badge.id, earnedAt: now,
                                   planName: planName, workoutName: workoutName,
                                   detail: progress.isBinary ? badge.hint : progress.label)
            context.insert(award)
        }
        return newlyEarned
    }
}
