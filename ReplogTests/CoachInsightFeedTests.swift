//
//  CoachInsightFeedTests.swift
//  ReplogTests
//
//  The coaching log only grows. These are the two rules that keep it readable: don't
//  remember the same thing twice, and group what is left so a long history stays navigable.
//

import Testing
import Foundation
@testable import Replog

struct CoachInsightFeedTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Fixed reference: 2026-06-30 (a Tuesday) at noon UTC.
    private var now: Date {
        DateComponents(calendar: cal, year: 2026, month: 6, day: 30, hour: 12).date!
    }

    private func daysAgo(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: -n, to: now)!
    }

    private struct Item {
        var date: Date
        var kind: CoachInsightKind = .sessionDebrief
    }

    private func insight(_ kind: CoachInsightKind, _ title: String) -> CoachInsight {
        CoachInsight(kind: kind, priority: .normal, title: title, body: "because")
    }

    private func recorded(_ kind: CoachInsightKind, _ summary: String, _ date: Date) -> CoachInsightFeed.Recorded {
        CoachInsightFeed.Recorded(kind: kind, summary: summary, date: date)
    }

    // MARK: - Not remembering the same thing twice

    @Test func theSameMilestoneIsNotCelebratedTwiceInOneDay() {
        // Two workouts finished on the same day, both crossing the same streak boundary.
        let already = [recorded(.milestone, "3-day streak!", now)]
        #expect(!CoachInsightFeed.shouldRecord(insight(.milestone, "3-day streak!"),
                                               given: already, now: now, calendar: cal))
    }

    @Test func aSecondDebriefTheSameDayIsNotWrittenTwice() {
        let already = [recorded(.sessionDebrief, "Session complete", now)]
        #expect(!CoachInsightFeed.shouldRecord(insight(.sessionDebrief, "Session complete"),
                                               given: already, now: now, calendar: cal))
    }

    @Test func aDifferentHeadlineTheSameDayIsStillWorthKeeping() {
        let already = [recorded(.milestone, "3-day streak!", now)]
        #expect(CoachInsightFeed.shouldRecord(insight(.milestone, "New personal best!"),
                                              given: already, now: now, calendar: cal))
        #expect(CoachInsightFeed.shouldRecord(insight(.sessionDebrief, "Session complete"),
                                              given: already, now: now, calendar: cal))
    }

    @Test func aMilestoneWaitsOutItsCooldownBeforeComingRoundAgain() {
        let recent = [recorded(.milestone, "3-day streak!", daysAgo(3))]
        #expect(!CoachInsightFeed.shouldRecord(insight(.milestone, "3-day streak!"),
                                               given: recent, now: now, calendar: cal))
        // Past the cooldown a rebuilt streak is genuinely worth celebrating again.
        let old = [recorded(.milestone, "3-day streak!", daysAgo(10))]
        #expect(CoachInsightFeed.shouldRecord(insight(.milestone, "3-day streak!"),
                                              given: old, now: now, calendar: cal))
    }

    @Test func aDebriefIsFineOnTheNextDay() {
        // Only milestones have a cooldown: every session deserves its own summary.
        let yesterday = [recorded(.sessionDebrief, "Session complete", daysAgo(1))]
        #expect(CoachInsightFeed.shouldRecord(insight(.sessionDebrief, "Session complete"),
                                              given: yesterday, now: now, calendar: cal))
    }

    @Test func anEmptyMemoryRecordsEverything() {
        #expect(CoachInsightFeed.shouldRecord(insight(.milestone, "First workout"),
                                              given: [], now: now, calendar: cal))
    }

    // MARK: - Grouping by when

    @Test func periodsDoNotOverlapAndPreferTheNarrowestTrue() {
        // Tuesday 30 June. This week starts Sunday 28 June.
        #expect(CoachInsightFeed.period(of: daysAgo(1), now: now, calendar: cal) == .thisWeek)
        #expect(CoachInsightFeed.period(of: daysAgo(4), now: now, calendar: cal) == .lastWeek)
        // 8 June: same month, but two weeks back.
        let earlierInMonth = DateComponents(calendar: cal, year: 2026, month: 6, day: 8, hour: 12).date!
        #expect(CoachInsightFeed.period(of: earlierInMonth, now: now, calendar: cal) == .thisMonth)
        let lastMonth = DateComponents(calendar: cal, year: 2026, month: 4, day: 2, hour: 12).date!
        #expect(CoachInsightFeed.period(of: lastMonth, now: now, calendar: cal) == .earlier)
    }

    @Test func periodSectionsRunNewestFirstAndSkipEmptyPeriods() {
        let items = [Item(date: daysAgo(1)), Item(date: daysAgo(4)), Item(date: daysAgo(2))]
        let sections = CoachInsightFeed.byPeriod(items, date: \.date, now: now, calendar: cal)

        #expect(sections.map(\.title) == ["This week", "Last week"])
        #expect(sections[0].items.count == 2)
        // Newest first inside the section.
        #expect(sections[0].items[0].date > sections[0].items[1].date)
        #expect(sections[1].items.count == 1)
    }

    @Test func nothingToShowProducesNoSections() {
        #expect(CoachInsightFeed.byPeriod([Item](), date: \.date, now: now, calendar: cal).isEmpty)
        #expect(CoachInsightFeed.byKind([Item](), kind: \.kind, date: \.date).isEmpty)
    }

    // MARK: - Grouping by what

    @Test func kindSectionsUseTheKindsOwnOrder() {
        let items = [
            Item(date: daysAgo(1), kind: .milestone),
            Item(date: daysAgo(2), kind: .stallAlert),
            Item(date: daysAgo(3), kind: .sessionDebrief),
            Item(date: daysAgo(4), kind: .milestone),
        ]
        let sections = CoachInsightFeed.byKind(items, kind: \.kind, date: \.date)

        // stallAlert(0) < sessionDebrief(3) < milestone(4) by sortRank.
        #expect(sections.map(\.title) == ["Plateaus", "Sessions", "Milestones"])
        #expect(sections.last?.items.count == 2)
        #expect(sections.last!.items[0].date > sections.last!.items[1].date)
    }

    @Test func everyKindHasAPluralGroupTitle() {
        for kind in CoachInsightKind.allCases {
            #expect(!kind.groupTitle.isEmpty)
        }
        // Titles are distinct, so two kinds never collapse into one section heading.
        #expect(Set(CoachInsightKind.allCases.map(\.groupTitle)).count == CoachInsightKind.allCases.count)
    }
}
