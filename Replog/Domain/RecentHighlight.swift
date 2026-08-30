//
//  RecentHighlight.swift
//  Replog
//
//  The best single thing in the log, and its story.
//
//  Today's "Recent Highlight" card is the athlete's heaviest estimated 1RM, and it used to
//  be computed inline in the view — a name, a number, and nothing behind it. Everything
//  that makes it *mean* something is already in history: what the rest of that session
//  looked like, which plan it was trained under, whether it beat anything, and how the lift
//  has moved since. This is that, as a value.
//
//  Pure, with the estimated-1RM resolution handed in as a closure. A bodyweight movement's
//  1RM depends on what the athlete weighed on the day (`LoadResolver`), which is a store
//  question — keeping it out here is what lets the whole thing be tested with plain values.
//

import Foundation

struct RecentHighlight: Equatable, Sendable {

    /// One session's estimated 1RM for the lift, for the trail behind the highlight.
    struct Point: Equatable, Sendable {
        var date: Date
        var e1rm: Int
    }

    var exId: String
    var date: Date
    var e1rm: Int
    var topWeightKg: Double
    var topReps: Int
    /// Every set logged in that session, in the order they were done.
    var sets: [RecordedSet]
    /// Captured at finish time, so a later rename can't orphan the attribution.
    var planName: String?
    var workoutName: String?
    /// The best estimated 1RM this lift had reached *before* that session. `nil` when the
    /// highlight was the first time it was ever logged.
    var previousBestE1RM: Int?
    /// Every session of this lift, oldest first — the line the highlight sits at the end of.
    var trail: [Point]

    /// Whether the highlight beat what the lift had done before. The first log of a
    /// movement is a baseline, not a record — the same rule the badges use.
    var isPersonalBest: Bool {
        guard let previousBestE1RM else { return false }
        return e1rm > previousBestE1RM
    }

    /// How much estimated 1RM the highlight added over the previous best. `nil` when there
    /// was nothing to beat, or when it did not beat it.
    var gainOverPreviousE1RM: Int? {
        guard let previousBestE1RM, e1rm > previousBestE1RM else { return nil }
        return e1rm - previousBestE1RM
    }

    /// How many times this lift has been logged.
    var sessionCount: Int { trail.count }

    /// The heaviest estimated 1RM in `entries`, with the rest of its session around it.
    ///
    /// Ties go to the most recent session: the card is a *recent* highlight, and repeating
    /// a best is the more interesting of two identical numbers. `e1rm` resolves an entry's
    /// estimated 1RM — for bodyweight movements that needs the athlete's weight on the day,
    /// which is why it is not read off the row.
    ///
    /// Entries with no estimable 1RM are ignored, so a log made entirely of timed holds
    /// has no highlight rather than a highlight of zero.
    static func best(in entries: [HistoryEntry], e1rm resolve: (HistoryEntry) -> Int) -> RecentHighlight? {
        // One resolution per entry, kept: `max(by:)` would call it twice per comparison on
        // a list that grows with every workout.
        //
        // A zero is not a small highlight, it is the absence of one: a timed hold logs no
        // reps, and an unloaded movement with no bodyweight credit resolves to nothing to
        // estimate from. Ranking those would put "0 est. 1RM" on Today as the best thing
        // the athlete has ever done — worse than showing no card at all.
        let scored = entries.map { (entry: $0, value: resolve($0)) }.filter { $0.value > 0 }
        guard let best = scored.reduce(nil, { (current: (entry: HistoryEntry, value: Int)?, candidate) in
            guard let current else { return candidate }
            if candidate.value > current.value { return candidate }
            if candidate.value == current.value, candidate.entry.date > current.entry.date { return candidate }
            return current
        }) else { return nil }

        let sameLift = scored.filter { $0.entry.exId == best.entry.exId }
            .sorted { $0.entry.date < $1.entry.date }
        let earlier = sameLift.filter { $0.entry.date < best.entry.date }.map(\.value)

        return RecentHighlight(
            exId: best.entry.exId,
            date: best.entry.date,
            e1rm: best.value,
            topWeightKg: best.entry.topW,
            topReps: best.entry.topR,
            sets: best.entry.sets,
            planName: best.entry.planName?.isEmpty == false ? best.entry.planName : nil,
            workoutName: best.entry.workoutName?.isEmpty == false ? best.entry.workoutName : nil,
            previousBestE1RM: earlier.max(),
            trail: sameLift.map { Point(date: $0.entry.date, e1rm: $0.value) })
    }
}
