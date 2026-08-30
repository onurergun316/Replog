//
//  RecentHighlightTests.swift
//  ReplogTests
//
//  Today's "Recent Highlight" — the heaviest estimated 1RM in the log, with the session
//  around it: what else was done that day, which plan it belonged to, what it beat, and
//  how the lift has moved since.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct RecentHighlightTests {

    private func entry(_ exId: String, daysAgo: Int, e1rm: Int, topW: Double = 100, topR: Int = 5,
                       sets: [RecordedSet] = [RecordedSet(w: 100, r: 5)],
                       planName: String? = nil, workoutName: String? = nil) -> HistoryEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return HistoryEntry(exId: exId, date: date, topW: topW, topR: topR, e1rm: e1rm,
                            sets: sets, workoutName: workoutName, planName: planName)
    }

    /// The stored `e1rm`, which is what the live resolver returns for a loaded movement.
    private func stored(_ entry: HistoryEntry) -> Int { entry.e1rm }

    // MARK: - Picking the highlight

    @Test func theHeaviestEstimatedOneRepMaxWins() throws {
        let entries = [entry("Bench", daysAgo: 10, e1rm: 100),
                       entry("Squat", daysAgo: 5, e1rm: 140),
                       entry("Row", daysAgo: 1, e1rm: 90)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.exId == "Squat")
        #expect(highlight.e1rm == 140)
    }

    @Test func aTieGoesToTheMoreRecentSession() throws {
        let entries = [entry("Bench", daysAgo: 30, e1rm: 120),
                       entry("Bench", daysAgo: 2, e1rm: 120)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.date == entries[1].date)
    }

    @Test func anEmptyLogHasNoHighlight() {
        #expect(RecentHighlight.best(in: [], e1rm: stored) == nil)
    }

    @Test func aLogWithNothingToEstimateFromHasNoHighlight() {
        // Timed holds: reps are zero, so there is no 1RM to estimate. The card must not
        // appear at all rather than announce "0 est. 1RM" as the athlete's best moment.
        let entries = [entry("Plank", daysAgo: 3, e1rm: 0, topW: 0, topR: 0),
                       entry("Side_Plank", daysAgo: 1, e1rm: 0, topW: 0, topR: 0)]

        #expect(RecentHighlight.best(in: entries, e1rm: stored) == nil)
    }

    @Test func anUnestimableEntryNeverOutranksARealOne() throws {
        // The zero rows are skipped entirely: they cannot win, and they cannot appear in
        // the lift's trail either.
        let entries = [entry("Plank", daysAgo: 1, e1rm: 0, topW: 0, topR: 0),
                       entry("Bench", daysAgo: 4, e1rm: 90),
                       entry("Bench", daysAgo: 2, e1rm: 110)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.exId == "Bench")
        #expect(highlight.e1rm == 110)
        #expect(highlight.trail.count == 2)
        #expect(highlight.previousBestE1RM == 90)
    }

    @Test func theResolverDecidesTheRanking() throws {
        // A bodyweight movement's 1RM depends on what the athlete weighed that day, so the
        // stored column is not the answer — whatever the caller resolves is.
        let entries = [entry("Pull_Up", daysAgo: 3, e1rm: 0),
                       entry("Bench", daysAgo: 1, e1rm: 100)]

        let highlight = try #require(RecentHighlight.best(in: entries) { $0.exId == "Pull_Up" ? 130 : $0.e1rm })
        #expect(highlight.exId == "Pull_Up")
        #expect(highlight.e1rm == 130)
    }

    // MARK: - The session around it

    @Test func theWholeSessionComesWithIt() throws {
        let sets = [RecordedSet(w: 100, r: 5), RecordedSet(w: 90, r: 8), RecordedSet(w: 80, r: 10)]
        let entries = [entry("Bench", daysAgo: 1, e1rm: 116, topW: 100, topR: 5, sets: sets,
                             planName: "PPL", workoutName: "Push Day")]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.sets == sets)
        #expect(highlight.topWeightKg == 100)
        #expect(highlight.topReps == 5)
        #expect(highlight.planName == "PPL")
        #expect(highlight.workoutName == "Push Day")
    }

    @Test func emptyAttributionReadsAsNoAttribution() throws {
        // Rows written before session attribution existed carry "" rather than nil.
        let entries = [entry("Bench", daysAgo: 1, e1rm: 116, planName: "", workoutName: "")]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.planName == nil)
        #expect(highlight.workoutName == nil)
    }

    // MARK: - What it beat

    @Test func aBestIsJudgedAgainstWhatCameBeforeIt() throws {
        let entries = [entry("Bench", daysAgo: 30, e1rm: 100),
                       entry("Bench", daysAgo: 14, e1rm: 108),
                       entry("Bench", daysAgo: 2, e1rm: 116)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.previousBestE1RM == 108)
        #expect(highlight.isPersonalBest)
        #expect(highlight.gainOverPreviousE1RM == 8)
    }

    @Test func theFirstTimeALiftIsLoggedIsABaselineNotARecord() throws {
        let entries = [entry("Bench", daysAgo: 1, e1rm: 116)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.previousBestE1RM == nil)
        #expect(!highlight.isPersonalBest)
        #expect(highlight.gainOverPreviousE1RM == nil)
    }

    @Test func aRepeatedBestIsNotAGain() throws {
        let entries = [entry("Bench", daysAgo: 20, e1rm: 116),
                       entry("Bench", daysAgo: 1, e1rm: 116)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.previousBestE1RM == 116)
        #expect(!highlight.isPersonalBest)
        #expect(highlight.gainOverPreviousE1RM == nil)
    }

    @Test func onlyEarlierSessionsCountAsPrevious() throws {
        // A session logged AFTER the highlight cannot be what it beat.
        let entries = [entry("Bench", daysAgo: 20, e1rm: 100),
                       entry("Bench", daysAgo: 10, e1rm: 130),
                       entry("Bench", daysAgo: 1, e1rm: 110)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.e1rm == 130)
        #expect(highlight.previousBestE1RM == 100)
    }

    // MARK: - The trail

    @Test func theTrailIsThisLiftOnly_oldestFirst() throws {
        let entries = [entry("Squat", daysAgo: 9, e1rm: 60),
                       entry("Bench", daysAgo: 20, e1rm: 100),
                       entry("Bench", daysAgo: 1, e1rm: 130),
                       entry("Bench", daysAgo: 10, e1rm: 110)]

        let highlight = try #require(RecentHighlight.best(in: entries, e1rm: stored))
        #expect(highlight.trail.map(\.e1rm) == [100, 110, 130])
        #expect(highlight.sessionCount == 3)
        #expect(highlight.trail.map(\.date) == highlight.trail.map(\.date).sorted())
    }
}
