//
//  BadgeEngine.swift
//  Replog
//
//  Deciding what has been earned, and how close the rest is.
//
//  Pure over `BadgeSnapshot`. Two answers come out: whether a criterion is met, and the
//  progress toward it as a fraction. Progress is not decoration — the research on
//  achievement systems is consistent that a visible, close next rung is what actually
//  drives the behaviour, so every ladder badge can show how far along it is.
//

import Foundation

enum BadgeEngine {

    // MARK: - Met or not

    /// Whether `criterion` is satisfied by the snapshot.
    static func isMet(_ criterion: BadgeCriterion, in snapshot: BadgeSnapshot) -> Bool {
        progress(criterion, in: snapshot).isComplete
    }

    /// Every badge whose criterion the snapshot satisfies.
    static func earned(from badges: [Badge] = BadgeCatalog.all,
                       in snapshot: BadgeSnapshot) -> [Badge] {
        badges.filter { isMet($0.criterion, in: snapshot) }
    }

    // MARK: - Progress

    /// How far along a criterion is. `current` and `target` are in the criterion's own
    /// units, so the UI can render "7 / 10" rather than a bare percentage.
    struct Progress: Equatable, Sendable {
        var current: Double
        var target: Double
        /// Some criteria are a yes or a no, with nothing meaningful in between.
        var isBinary: Bool

        var isComplete: Bool { current >= target }

        /// 0 to 1. A binary criterion is 0 or 1, never a teasing 60 percent.
        var fraction: Double {
            guard target > 0 else { return isComplete ? 1 : 0 }
            return min(1, max(0, current / target))
        }

        /// "7 / 10" for a countable ladder, empty for a yes-or-no.
        var label: String {
            guard !isBinary else { return "" }
            return "\(format(current)) / \(format(target))"
        }

        private func format(_ value: Double) -> String {
            if value >= 1000 {
                return value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
            }
            return value == value.rounded()
                ? String(Int(value))
                : value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private static func count(_ current: Int, _ target: Int) -> Progress {
        Progress(current: Double(current), target: Double(max(1, target)), isBinary: false)
    }

    private static func amount(_ current: Double, _ target: Double) -> Progress {
        Progress(current: current, target: max(0.0001, target), isBinary: false)
    }

    private static func yesNo(_ met: Bool) -> Progress {
        Progress(current: met ? 1 : 0, target: 1, isBinary: true)
    }

    /// Progress toward one criterion.
    static func progress(_ criterion: BadgeCriterion, in s: BadgeSnapshot) -> Progress {
        switch criterion {
        case .workouts(let n):          return count(s.totalWorkouts, n)
        case .dayStreak(let n):         return count(s.dayStreak, n)
        case .weekStreak(let n):        return count(s.weekStreak, n)
        case .perfectWeeks(let n):      return count(s.perfectWeeks, n)

        case .earlyStart(let sessions, let days):
            return count(s.sessionsInFirst(days: days), sessions)

        case .personalBests(let n):     return count(s.personalBestTotal, n)
        case .bestsInOneSession(let n): return count(s.bestPersonalBestsInOneSession, n)
        case .bodyweightMultiple(let pattern, let times):
            return amount(s.bestRatio(for: pattern), times)

        case .tonnage(let kg):          return amount(s.tonnageKg, kg)
        case .sessionTonnage(let kg):   return amount(s.bestSessionTonnageKg, kg)
        case .sets(let n):              return count(s.setTotal, n)
        case .reps(let n):              return count(s.repTotal, n)

        case .distinctExercises(let n): return count(s.distinctExercises, n)
        case .distinctMuscles(let n):   return count(s.distinctMuscles, n)
        case .distinctEquipment(let n): return count(s.distinctEquipment, n)
        case .distinctCategories(let n):return count(s.distinctCategories, n)
        case .distinctCompounds(let n): return count(s.distinctCompounds, n)

        case .sessionsBefore(let hour, let n):
            return count(s.sessions(startedBefore: hour), n)
        case .sessionsAfter(let hour, let n):
            return count(s.sessions(startedAtOrAfter: hour), n)
        case .everyWeekday:
            return count(s.weekdaysTrained.count, 7)
        case .weekendSessions(let n):   return count(s.weekendSessions, n)
        case .repRangeSweep:            return yesNo(s.hasRepRangeSweep)

        case .pushPullBalance(let withinPercent, let minTonnage):
            // Both sides have to carry real work before a ratio says anything, so this
            // stays a yes or no rather than creeping up on a single pressing session.
            let enough = min(s.pushTonnageKg, s.pullTonnageKg) >= minTonnage
            let even = (s.pushPullSpreadPercent ?? .infinity) <= withinPercent
            return yesNo(enough && even)

        case .comeback(let days):       return count(s.longestReturnGapDays, days)
        case .dormantBest(let days):    return count(s.longestDormantBestDays, days)
        case .monthsActive(let n):      return count(s.monthsActive, n)
        case .sessionMinutes(let n):    return count(s.bestSessionMinutes, n)

        case .bodyweightCheckIns(let n): return count(s.bodyweightCheckIns, n)
        case .readinessCheckIns(let n):  return count(s.readinessCheckIns, n)
        case .customExercises(let n):    return count(s.customExercises, n)
        case .plansBuilt(let n):         return count(s.plansBuilt, n)
        }
    }

    // MARK: - What to show next

    /// The unearned badges closest to being earned, most nearly complete first.
    ///
    /// A next rung the athlete can see is the point: an empty board with fifty locked
    /// silhouettes is discouraging, one that says "3 of 5 sessions" is an invitation.
    /// Badges with no progress at all are excluded, and so are curiosities, which are
    /// supposed to arrive unannounced.
    static func upNext(from badges: [Badge] = BadgeCatalog.all,
                       in snapshot: BadgeSnapshot, limit: Int = 3) -> [Badge] {
        var candidates: [(badge: Badge, fraction: Double)] = []
        for badge in badges where badge.family != .curiosities {
            let progress = progress(badge.criterion, in: snapshot)
            guard !progress.isComplete, progress.fraction > 0 else { continue }
            candidates.append((badge, progress.fraction))
        }
        candidates.sort { lhs, rhs in
            lhs.fraction == rhs.fraction ? lhs.badge.id < rhs.badge.id : lhs.fraction > rhs.fraction
        }
        return candidates.prefix(limit).map(\.badge)
    }
}
