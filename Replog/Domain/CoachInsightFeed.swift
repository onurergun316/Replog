//
//  CoachInsightFeed.swift
//  Replog
//
//  Turning the coach's memory into something readable.
//
//  Every surfaced insight is written to the coaching log, and the log only grows. Rendered
//  as a flat list it pushed the Profile screen longer every week and repeated itself: four
//  copies of "3-day streak!" in a row says nothing the first one didn't.
//
//  Two pure pieces fix that. `shouldRecord` decides what is worth remembering in the first
//  place, so the same milestone is not written twice. `byPeriod`/`byKind` group what is left
//  into navigable sections. Both are generic over the item, so they are testable without a
//  store and reusable for anything dated.
//

import Foundation

enum CoachInsightFeed {

    // MARK: - Grouping

    /// A titled run of items. `id` is the title, which is unique within one grouping.
    struct Section<Item>: Identifiable {
        var title: String
        var items: [Item]
        var id: String { title }
    }

    /// How recent an insight is, in the terms an athlete actually thinks in.
    enum Period: Int, CaseIterable {
        case thisWeek, lastWeek, thisMonth, earlier

        var title: String {
            switch self {
            case .thisWeek:  return "This week"
            case .lastWeek:  return "Last week"
            case .thisMonth: return "This month"
            case .earlier:   return "Earlier"
            }
        }
    }

    /// Which period a date falls in, relative to `now`.
    ///
    /// The periods are checked in order and do not overlap: something from three days ago is
    /// "This week" even though it is also within this month.
    static func period(of date: Date, now: Date = Date(), calendar: Calendar = .current) -> Period {
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
           calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) { return .lastWeek }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .earlier
    }

    /// Items grouped into periods, newest period first. Empty periods are dropped, and each
    /// section keeps its items newest first.
    static func byPeriod<Item>(_ items: [Item], date: (Item) -> Date,
                               now: Date = Date(), calendar: Calendar = .current) -> [Section<Item>] {
        var buckets: [Period: [Item]] = [:]
        for item in items {
            buckets[period(of: date(item), now: now, calendar: calendar), default: []].append(item)
        }
        return Period.allCases.compactMap { period in
            guard let bucket = buckets[period], !bucket.isEmpty else { return nil }
            return Section(title: period.title, items: bucket.sorted { date($0) > date($1) })
        }
    }

    /// Items grouped by what kind of insight they are, in the kinds' own display order.
    /// Empty kinds are dropped and each section keeps its items newest first.
    static func byKind<Item>(_ items: [Item], kind: (Item) -> CoachInsightKind,
                             date: (Item) -> Date) -> [Section<Item>] {
        var buckets: [CoachInsightKind: [Item]] = [:]
        for item in items { buckets[kind(item), default: []].append(item) }
        return CoachInsightKind.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { kind in
                guard let bucket = buckets[kind], !bucket.isEmpty else { return nil }
                return Section(title: kind.groupTitle, items: bucket.sorted { date($0) > date($1) })
            }
    }

    // MARK: - What is worth remembering

    /// An insight already written to the coaching memory, reduced to what dedup needs.
    struct Recorded: Equatable, Sendable {
        var kind: CoachInsightKind
        var summary: String
        var date: Date
    }

    /// How long a milestone stays "already celebrated". Streaks rebuild, so the same
    /// headline may legitimately come round again — just not twice in the same week.
    static let milestoneCooldownDays = 7

    /// Whether `insight` should be written to the coaching memory at all.
    ///
    /// Two finishes in one day both produce a session debrief and, at a streak boundary, the
    /// same milestone; writing both leaves the athlete reading the identical card twice. So:
    /// nothing repeats itself on the same day, and a milestone additionally waits out a
    /// cooldown before it may be celebrated again.
    static func shouldRecord(_ insight: CoachInsight, given existing: [Recorded],
                             now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let sameHeadline = existing.filter { $0.kind == insight.kind && $0.summary == insight.title }
        guard !sameHeadline.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) else {
            return false
        }
        guard insight.kind == .milestone else { return true }
        guard let cooldownStart = calendar.date(byAdding: .day, value: -milestoneCooldownDays, to: now) else {
            return true
        }
        return !sameHeadline.contains { $0.date > cooldownStart }
    }
}

extension CoachingLog {
    /// The `CoachInsightKind` a recorded coach-insight log represents (stored in payload tags),
    /// defaulting to a session debrief for older/plain records.
    var insightKind: CoachInsightKind {
        for tag in payload.tags {
            if let kind = CoachInsightKind(rawValue: tag) { return kind }
        }
        return .sessionDebrief
    }
}

extension CoachInsightKind {
    /// Section heading when the feed is grouped by type. Plural and plain-language, since
    /// it labels a run of cards rather than a single one.
    var groupTitle: String {
        switch self {
        case .sessionDebrief:   return "Sessions"
        case .stallAlert:       return "Plateaus"
        case .adherenceInsight: return "Consistency"
        case .milestone:        return "Milestones"
        case .bodyweightTrend:  return "Bodyweight"
        case .checkInPrompt:    return "Check-ins"
        case .readinessTrend:   return "Readiness"
        case .welcome:          return "Welcome"
        }
    }
}
