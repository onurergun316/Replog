//
//  MonthlyReportComposer.swift
//  Replog
//
//  The monthly training rollup: a pure composition of a completed calendar month's story —
//  adherence %, sets & volume, the month's biggest e1RM movers, new records, bodyweight — plus
//  ONE key insight and ONE recommended adjustment, into the markdown `CoachReportView` renders.
//  `publishIfDue` writes it once per completed month into the coaching memory
//  (`CoachingLog(kind: .monthlyReport)`). Mirrors `WeeklyReportComposer`; reuses its
//  `PersonalRecord` detection.
//

import Foundation
import SwiftData

@MainActor
enum MonthlyReportComposer {

    /// Payload metric names persisted on the published log. `monthStart` is the dedup key.
    enum MetricKey {
        static let monthStart = "monthStart"
        static let sets = "sets"
        static let volumeKg = "volumeKg"
        static let daysTrained = "daysTrained"
        static let adherencePct = "adherencePct"
        static let records = "records"
    }

    static let maxMovers = 3

    // MARK: - Value types

    struct MonthStats: Equatable {
        var daysTrained: Int
        var scheduledCount: Int
        var scheduledDone: Int
        var totalSets: Int
        var totalVolumeKg: Double

        /// Adherence as a whole percent, nil when nothing was scheduled.
        var adherencePct: Int? {
            guard scheduledCount > 0 else { return nil }
            return Int((Double(scheduledDone) / Double(scheduledCount) * 100).rounded())
        }
    }

    /// A lift's estimated-1RM movement within the month (first logged → last logged).
    struct Mover: Equatable {
        var exId: String
        var fromE1rm: Int
        var toE1rm: Int
        var delta: Int { toE1rm - fromE1rm }
    }

    struct Report: Equatable {
        var monthStart: Date
        var headline: String
        var markdown: String
        var stats: MonthStats
        var records: [WeeklyReportComposer.PersonalRecord]
        var movers: [Mover]
    }

    // MARK: - Composition (pure)

    /// Composes the report for the calendar month containing `monthStart` (a start-of-month
    /// date). Returns nil for an idle month (nothing trained).
    static func compose(
        monthStart: Date,
        history: [HistoryEntry],
        doneDates: [Date],
        scheduledDays: Set<Weekday>,
        coachingLogs: [CoachingLog],
        bodyweightEntries: [BodyweightEntry],
        goal: Goal,
        units: Units,
        load: LoadResolver? = nil,
        calendar: Calendar = .current
    ) -> Report? {
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        let month = monthStart..<monthEnd

        // Defaulted in-body rather than as a default argument: default-argument
        // expressions are evaluated outside the callee's actor isolation.
        let resolver = load ?? .stored
        let inMonth = history.filter { month.contains($0.date) }
        var trainedDays = Set(doneDates.filter(month.contains).map { calendar.startOfDay(for: $0) })
        trainedDays.formUnion(inMonth.map { calendar.startOfDay(for: $0.date) })
        guard !trainedDays.isEmpty else { return nil }

        // Scheduled workout dates that fell in the month.
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let scheduledDates = Set((0..<dayCount).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            return scheduledDays.contains(Weekday.from(date, calendar: calendar))
                ? calendar.startOfDay(for: date) : nil
        })

        var totalSets = 0
        var totalVolumeKg = 0.0
        for entry in inMonth {
            let sets = entry.sets
            totalSets += sets.count
            for set in sets { totalVolumeKg += resolver.volumeKg(exId: entry.exId, set: set, on: entry.date) }
        }
        let stats = MonthStats(
            daysTrained: trainedDays.count,
            scheduledCount: scheduledDates.count,
            scheduledDone: scheduledDates.intersection(trainedDays).count,
            totalSets: totalSets,
            totalVolumeKg: totalVolumeKg)

        let records = WeeklyReportComposer.personalRecords(inWeek: inMonth, history: history, weekStart: monthStart)
        let movers = topMovers(inMonth: inMonth)
        let insight = keyInsight(month: month, stats: stats, records: records, movers: movers,
                                 coachingLogs: coachingLogs)
        let adjustment = recommendedAdjustment(month: month, stats: stats, records: records,
                                               coachingLogs: coachingLogs)

        let headline = "Month in review · \(monthText(monthStart, calendar: calendar))"
        let body = markdown(headline: headline, stats: stats, records: records, movers: movers,
                            insight: insight, adjustment: adjustment,
                            bodyweightEntries: bodyweightEntries, monthEnd: monthEnd,
                            goal: goal, units: units)
        return Report(monthStart: monthStart, headline: headline, markdown: body,
                      stats: stats, records: records, movers: movers)
    }

    /// The biggest positive estimated-1RM moves within the month (first vs last logged e1RM
    /// per loaded lift), largest first, capped at `maxMovers`.
    static func topMovers(inMonth: [HistoryEntry]) -> [Mover] {
        var movers: [Mover] = []
        for (exId, entries) in Dictionary(grouping: inMonth.filter { $0.topW > 0 }, by: \.exId) {
            let byDate = entries.sorted { $0.date < $1.date }
            guard let first = byDate.first, let last = byDate.last, byDate.count >= 2 else { continue }
            let mover = Mover(exId: exId, fromE1rm: first.e1rm, toE1rm: last.e1rm)
            if mover.delta > 0 { movers.append(mover) }
        }
        return Array(movers.sorted {
            $0.delta != $1.delta ? $0.delta > $1.delta : $0.exId < $1.exId
        }.prefix(maxMovers))
    }

    /// The single key insight, by priority: an in-month stall memory, then the top record,
    /// then the biggest mover, then an adherence-based note.
    static func keyInsight(
        month: Range<Date>, stats: MonthStats,
        records: [WeeklyReportComposer.PersonalRecord], movers: [Mover],
        coachingLogs: [CoachingLog]
    ) -> String {
        if let stall = coachingLogs
            .filter({ ($0.kind == .plateau || $0.kind == .deload) && month.contains($0.date) })
            .max(by: { $0.date < $1.date }) {
            return stall.summary
        }
        if let top = records.first {
            return "Your standout this month was a new best on \(ReportComposer.prettyName(top.exId))."
        }
        if let mover = movers.first {
            return "\(ReportComposer.prettyName(mover.exId)) climbed \(mover.delta) kg in estimated 1RM this month."
        }
        if let pct = stats.adherencePct {
            return "You completed \(pct)% of your scheduled sessions this month."
        }
        return "You logged \(stats.daysTrained) training days this month."
    }

    /// The single recommended adjustment for next month.
    static func recommendedAdjustment(
        month: Range<Date>, stats: MonthStats,
        records: [WeeklyReportComposer.PersonalRecord], coachingLogs: [CoachingLog]
    ) -> String {
        if let stall = coachingLogs
            .filter({ ($0.kind == .plateau || $0.kind == .deload) && month.contains($0.date) })
            .max(by: { $0.date < $1.date }) {
            return "Act on the stall the coach flagged: \(stall.summary)"
        }
        if let pct = stats.adherencePct, pct < 70, stats.scheduledCount > 0 {
            return "Adherence was \(pct)% — consider scheduling fewer days you can reliably hit, then build back up."
        }
        if !records.isEmpty {
            return "You're progressing well — add a set to your main lifts or nudge the load up next month."
        }
        return "Hold the pattern and prioritise consistency — small, repeated sessions compound."
    }

    // MARK: - Publishing (store boundary)

    /// Start of the calendar month that contains `date`.
    static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    /// Start of the most recently *completed* month (the month before `now`'s).
    static func lastCompletedMonthStart(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let thisMonth = startOfMonth(for: now, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .month, value: -1, to: thisMonth)
    }

    /// Whether a report for `monthStart` is already published among `logs`.
    static func isPublished(monthStart: Date, in logs: [CoachingLog]) -> Bool {
        let target = monthStart.timeIntervalSinceReferenceDate
        return logs.contains { log in
            log.kind == .monthlyReport &&
            log.payload[metric: MetricKey.monthStart].map { abs($0 - target) < 43_200 } == true
        }
    }

    /// Composes and records last month's report unless already published or the month was
    /// idle. Idempotent per month. Saves.
    @discardableResult
    static func publishIfDue(
        context: ModelContext, now: Date = Date(), calendar: Calendar = .current
    ) -> CoachingLog? {
        guard let monthStart = lastCompletedMonthStart(now: now, calendar: calendar),
              !isPublished(monthStart: monthStart, in: context.coachingLogs(kind: .monthlyReport))
        else { return nil }

        let profile = context.userProfile()
        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
        guard let report = compose(
            monthStart: monthStart,
            history: history,
            doneDates: profile.doneDates,
            scheduledDays: StreakEngine.scheduledDays(in: context.allPlans()),
            coachingLogs: context.coachingLogs(),
            bodyweightEntries: context.bodyweightEntries(),
            goal: profile.goal,
            units: context.appSettings().units,
            load: .live(catalog: .shared, bodyweightEntries: context.bodyweightEntries()),
            calendar: calendar
        ) else { return nil }

        let log = context.recordCoaching(
            .monthlyReport, summary: report.headline, date: now,
            payload: CoachingPayload(metrics: [
                MetricKey.monthStart: monthStart.timeIntervalSinceReferenceDate,
                MetricKey.sets: Double(report.stats.totalSets),
                MetricKey.volumeKg: report.stats.totalVolumeKg,
                MetricKey.daysTrained: Double(report.stats.daysTrained),
                MetricKey.adherencePct: Double(report.stats.adherencePct ?? 0),
                MetricKey.records: Double(report.records.count),
            ]),
            bodyMarkdown: report.markdown
        )
        try? context.save()
        return log
    }

    // MARK: - Rendering

    private static func markdown(
        headline: String, stats: MonthStats,
        records: [WeeklyReportComposer.PersonalRecord], movers: [Mover],
        insight: String, adjustment: String,
        bodyweightEntries: [BodyweightEntry], monthEnd: Date, goal: Goal, units: Units
    ) -> String {
        var out = "# \(headline)\n\n"

        out += "## Training\n"
        if let pct = stats.adherencePct {
            out += "- **\(pct)% adherence** — \(stats.scheduledDone) of \(stats.scheduledCount) scheduled workouts\n"
        } else {
            out += "- **\(stats.daysTrained)** training day\(stats.daysTrained == 1 ? "" : "s") logged\n"
        }
        out += "- **\(stats.totalSets) set\(stats.totalSets == 1 ? "" : "s")** · " +
               "**\(formatVolume(kg: stats.totalVolumeKg, units: units))** total volume\n"
        // A tonnage nobody can picture is a tonnage nobody remembers.
        if let picture = VolumeNarrator.tonnageSentence(kg: stats.totalVolumeKg, catalog: .shared,
                                                        seed: VolumeNarrator.seed(for: monthEnd)) {
            out += "- \(picture)\n"
        }
        out += "\n"

        if !movers.isEmpty {
            out += "## Biggest movers\n"
            for mover in movers {
                out += "- **\(ReportComposer.prettyName(mover.exId))** — est. 1RM \(mover.fromE1rm) → \(mover.toE1rm) (+\(mover.delta))\n"
            }
            out += "\n"
        }

        if !records.isEmpty {
            out += "## New records\n"
            for record in records {
                let name = ReportComposer.prettyName(record.exId)
                out += record.isRepRecord
                    ? "- **\(name)** — \(record.value) reps, up from \(record.previousBest)\n"
                    : "- **\(name)** — est. 1RM \(record.value), up from \(record.previousBest)\n"
            }
            out += "\n"
        }

        let weighIns = bodyweightEntries.filter { $0.date < monthEnd }
        if let snapshot = BodyweightTracker.snapshot(entries: weighIns) {
            out += "## Bodyweight\n- **\(Formulas.formatBodyweight(kg: snapshot.currentKg, units: units))**"
            if let rate = snapshot.weeklyRateKg {
                let f = Formulas.formatBodyweight(kg: abs(rate), units: units)
                switch snapshot.direction {
                case .up: out += " · trending up \(f)/week"
                case .down: out += " · trending down \(f)/week"
                case .flat: out += " · holding steady"
                case .none: break
                }
            }
            out += "\n\n"
        }

        out += "## Key insight\n\(insight)\n\n"
        out += "## Recommended adjustment\n\(adjustment)\n\n"
        out += "> \(encouragement(for: goal))\n"
        return out
    }

    private static func encouragement(for goal: Goal) -> String {
        switch goal {
        case .buildMuscle: return "A month of honest work adds up. Same lifts, a little more each week — see you next month."
        case .loseWeight:  return "The monthly trend is the truth. Keep the sessions coming and let the average fall."
        case .recomp:      return "Recomposition rewards patience. Another month in the bank — stay the course."
        case .sport:       return "Durability and strength compound. Carry this month's base into next."
        }
    }

    /// "June 2026" for the month containing `monthStart`.
    private static func monthText(_ monthStart: Date, calendar: Calendar) -> String {
        monthStart.formatted(Date.FormatStyle().month(.wide).year())
    }

    private static func formatVolume(kg: Double, units: Units) -> String {
        let value = units == .kg ? kg : kg * 2.20462
        return "\(Int(value.rounded()).formatted(.number.grouping(.automatic)))\(units.label)"
    }
}
