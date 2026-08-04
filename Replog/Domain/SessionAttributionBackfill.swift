//
//  SessionAttributionBackfill.swift
//  Replog
//
//  A one-time repair for history finished before sessions recorded where they came from.
//
//  `SessionFinisher` stamps `workoutName`/`planName`/`workoutId` onto every entry it
//  writes, so Progress can say "Day 2" instead of "Workout". Anything finished before
//  that shipped has none of it, and there is no rename to undo — the fields were simply
//  never written. The names are still recoverable, though: a session *is* the list of
//  exercises it logged, and the plan that produced it is still in the store. This scores
//  each session against every workout and stamps the one that explains it.
//
//  Runs once, guarded by a version on `AppSettings`, and only ever fills in blanks — an
//  entry that already knows its workout is never touched.
//

import Foundation
import SwiftData

/// Which workout a finished session came from, recovered from what it contained.
/// Pure: the matching rules are testable without a store.
enum SessionAttribution {

    /// A workout a session could have been built from.
    struct Candidate: Equatable {
        var id: UUID
        var workoutName: String
        var planName: String
        var exIds: [String]
    }

    /// How well a candidate explains a session.
    ///
    /// Containment leads and overlap breaks the tie. A partial finish logs a subset of
    /// its workout, so it is fully *contained* by it while sharing only half the union —
    /// ranking on overlap alone would leave every abandoned session unnamed. Overlap
    /// then separates a workout that explains the session exactly from one that merely
    /// happens to contain it among thirty other exercises.
    struct Score: Comparable, Equatable {
        var containment: Double
        var overlap: Double

        static func < (lhs: Score, rhs: Score) -> Bool {
            lhs.containment == rhs.containment ? lhs.overlap < rhs.overlap
                                               : lhs.containment < rhs.containment
        }
    }

    /// How much of the session the workout has to account for before its name may be
    /// borrowed. Below this the athlete has swapped so much that calling it "Day 2"
    /// would be an invention.
    static let minimumContainment = 0.6

    static func score(sessionExIds: Set<String>, candidate: Candidate) -> Score {
        let workout = Set(candidate.exIds)
        guard !sessionExIds.isEmpty, !workout.isEmpty else { return Score(containment: 0, overlap: 0) }
        let shared = Double(sessionExIds.intersection(workout).count)
        let union = Double(sessionExIds.union(workout).count)
        return Score(containment: shared / Double(sessionExIds.count),
                     overlap: union == 0 ? 0 : shared / union)
    }

    /// The workout that best explains `sessionExIds`, or `nil` when nothing does.
    ///
    /// A tie returns `nil` on purpose: two workouts that explain the session equally well
    /// cannot be told apart, and a coin-flip would put a wrong name on real history.
    static func match(sessionExIds: [String], candidates: [Candidate]) -> Candidate? {
        let logged = Set(sessionExIds)
        guard !logged.isEmpty else { return nil }
        let scored = candidates
            .map { (candidate: $0, score: score(sessionExIds: logged, candidate: $0)) }
            .filter { $0.score.containment >= minimumContainment }
            .sorted { $0.score > $1.score }
        guard let best = scored.first else { return nil }
        if scored.count > 1, scored[1].score == best.score { return nil }
        return best.candidate
    }
}

@MainActor
enum SessionAttributionBackfill {

    /// Bump to re-run the repair on devices that already ran an earlier version.
    ///
    /// v2 additionally stamps `HistoryEntry.planId`, which scopes a logged number to the plan
    /// it was trained under. Without it every pre-existing row is unattributable, and an
    /// upgrading athlete would lose carry-forward on every lift they have ever logged.
    static let version = 2

    /// Names every unattributed session it can, then resolves each entry's plan from its
    /// workout. Returns the number of history entries updated.
    @discardableResult
    static func run(context: ModelContext) -> Int {
        let settings = context.appSettings()
        guard settings.sessionAttributionVersion < Self.version else { return 0 }
        settings.sessionAttributionVersion = Self.version

        let plans = context.allPlans()
        let candidates = plans.flatMap { plan in
            plan.orderedWorkouts.map {
                SessionAttribution.Candidate(id: $0.id, workoutName: $0.name,
                                             planName: plan.name,
                                             exIds: $0.orderedItems.map(\.exId))
            }
        }
        guard !candidates.isEmpty else { return 0 }

        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
        var updated = 0
        for session in ProgressAnalytics.sessions(history: history) {
            guard session.workoutName == nil else { continue }
            guard let match = SessionAttribution.match(
                sessionExIds: session.entries.map(\.exId), candidates: candidates) else { continue }
            for entry in session.entries {
                entry.workoutId = entry.workoutId ?? match.id
                entry.workoutName = match.workoutName.isEmpty ? nil : match.workoutName
                entry.planName = entry.planName ?? (match.planName.isEmpty ? nil : match.planName)
                updated += 1
            }
        }
        updated += backfillPlanIds(history: history, plans: plans)
        try? context.save()
        return updated
    }

    /// Resolves `planId` for every entry that knows its workout but not its plan — which is
    /// every row written before plan scoping existed, plus the ones the pass above just
    /// named. An entry whose workout is gone stays `nil` on purpose: it is real training that
    /// happened, but it can no longer speak for any plan's prescription.
    private static func backfillPlanIds(history: [HistoryEntry], plans: [Plan]) -> Int {
        var planIdByWorkout: [UUID: UUID] = [:]
        for plan in plans {
            for workout in plan.workouts { planIdByWorkout[workout.id] = plan.id }
        }
        guard !planIdByWorkout.isEmpty else { return 0 }

        var updated = 0
        for entry in history where entry.planId == nil {
            guard let workoutId = entry.workoutId, let planId = planIdByWorkout[workoutId] else { continue }
            entry.planId = planId
            updated += 1
        }
        return updated
    }
}
