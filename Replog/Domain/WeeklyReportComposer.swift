//
//  WeeklyReportComposer.swift
//  Replog
//
//  The weekly training report: a pure composition of a completed week's story —
//  adherence, sets & volume, new records, bodyweight trend, and one coaching note —
//  into the markdown `CoachReportView` renders. `publishIfDue` writes it once per
//  completed week into the coaching memory (`CoachingLog(kind: .weeklyReport)`),
//  where the Profile tab lists it alongside the AI plan reports.
//

import Foundation
import SwiftData

@MainActor
enum WeeklyReportComposer {

    /// Payload metric names persisted on the published `CoachingLog` (also read by the
    /// Profile list row). `weekStart` doubles as the once-per-week dedup key.
    enum MetricKey {
        static let weekStart = "weekStart"
        static let sets = "sets"
        static let volumeKg = "volumeKg"
        static let daysTrained = "daysTrained"
        static let daysScheduled = "daysScheduled"
        static let records = "records"
    }

    /// The report never lists more than this many new records (biggest jumps first).
    static let maxRecords = 5

    // MARK: - Value types

    /// The week's headline numbers (also persisted into the log's payload metrics).
    struct WeekStats: Equatable {
        /// Distinct training days in the week (completed days ∪ days with logged sets).
        var daysTrained: Int
        /// Scheduled workouts that week (one per scheduled weekday).
        var daysScheduled: Int
        /// Scheduled workouts that were actually trained.
        var scheduledDone: Int
        var totalSets: Int
        var totalVolumeKg: Double
        /// Sets logged the week before (nil when that week had none).
        var previousWeekSets: Int?

        /// Training days beyond the schedule (extra sessions).
        var extraDays: Int { max(0, daysTrained - scheduledDone) }
        var isPerfectWeek: Bool { daysScheduled > 0 && scheduledDone >= daysScheduled }
    }

    /// A new best within the week: est. 1RM for loaded lifts, top reps for bodyweight lifts.
    struct PersonalRecord: Equatable {
        var exId: String
        var value: Int
        var previousBest: Int
        var isRepRecord: Bool
    }

    struct Report: Equatable {
        var weekStart: Date
        /// One-line title, stored as the log's `summary` ("Week in review · Jun 22 – Jun 28").
        var headline: String
        var markdown: String
        var stats: WeekStats
        var records: [PersonalRecord]
    }

    // MARK: - Composition (pure)

    /// Composes the report for the week starting `weekStart` (a start-of-day Sunday, per
    /// `StreakEngine.startOfWeek`). Returns nil when nothing was trained that week —
    /// an idle week publishes no report.
    static func compose(
        weekStart: Date,
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
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        let week = weekStart..<weekEnd

        // Defaulted in-body rather than as a default argument: default-argument
        // expressions are evaluated outside the callee's actor isolation.
        let resolver = load ?? .stored
        let inWeek = history.filter { week.contains($0.date) }
        var trainedDays = Set(doneDates.filter(week.contains).map { calendar.startOfDay(for: $0) })
        trainedDays.formUnion(inWeek.map { calendar.startOfDay(for: $0.date) })
        guard !trainedDays.isEmpty else { return nil }

        let scheduledDates = Set((0..<7).compactMap { offset -> Date? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return scheduledDays.contains(Weekday.from(date, calendar: calendar)) ? date : nil
        })

        let previousWeek = (calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart)..<weekStart
        let previousSets = history.filter { previousWeek.contains($0.date) }
            .reduce(0) { $0 + $1.sets.count }

        var totalSets = 0
        var totalVolumeKg = 0.0
        for entry in inWeek {
            let sets = entry.sets
            totalSets += sets.count
            for set in sets { totalVolumeKg += resolver.volumeKg(exId: entry.exId, set: set, on: entry.date) }
        }
        let stats = WeekStats(
            daysTrained: trainedDays.count,
            daysScheduled: scheduledDates.count,
            scheduledDone: scheduledDates.intersection(trainedDays).count,
            totalSets: totalSets,
            totalVolumeKg: totalVolumeKg,
            previousWeekSets: previousSets > 0 ? previousSets : nil
        )

        let records = personalRecords(inWeek: inWeek, history: history, weekStart: weekStart)
        let note = coachingNote(week: week, stats: stats, records: records,
                                inWeek: inWeek, history: history, coachingLogs: coachingLogs)
        let headline = "Week in review · \(rangeText(weekStart: weekStart, calendar: calendar))"
        let body = markdown(headline: headline, stats: stats, records: records, note: note,
                            bodyweightEntries: bodyweightEntries, weekEnd: weekEnd,
                            goal: goal, units: units)
        return Report(weekStart: weekStart, headline: headline, markdown: body,
                      stats: stats, records: records)
    }

    /// New bests set during the week, biggest improvement first, capped at `maxRecords`.
    /// A lift with no pre-week baseline is a first log, not a record (week one would
    /// otherwise "PR" every movement). Bodyweight-only lifts (top weight 0) record on
    /// top reps, since their stored e1RM is always 0 (the B1/B3 convention).
    static func personalRecords(
        inWeek: [HistoryEntry], history: [HistoryEntry], weekStart: Date
    ) -> [PersonalRecord] {
        let priorByEx = Dictionary(grouping: history.filter { $0.date < weekStart }, by: \.exId)
        var records: [PersonalRecord] = []
        for (exId, entries) in Dictionary(grouping: inWeek, by: \.exId) {
            let prior = priorByEx[exId] ?? []
            if let weekBest = entries.filter({ $0.topW > 0 }).map(\.e1rm).max() {
                guard let priorBest = prior.filter({ $0.topW > 0 }).map(\.e1rm).max(),
                      weekBest > priorBest else { continue }
                records.append(PersonalRecord(exId: exId, value: weekBest,
                                              previousBest: priorBest, isRepRecord: false))
            } else {
                let weekBestReps = entries.map(\.topR).max() ?? 0
                guard let priorBest = prior.filter({ $0.topW == 0 }).map(\.topR).max(),
                      weekBestReps > priorBest else { continue }
                records.append(PersonalRecord(exId: exId, value: weekBestReps,
                                              previousBest: priorBest, isRepRecord: true))
            }
        }
        return Array(
            records.sorted {
                let (a, b) = ($0.value - $0.previousBest, $1.value - $1.previousBest)
                if a != b { return a > b }
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.exId < $1.exId
            }
            .prefix(maxRecords)
        )
    }

    /// The single coaching note, by priority: the trainer's own in-week stall memory
    /// (most actionable), then the week's records, then a quietly progressing lift,
    /// then an adherence nudge.
    static func coachingNote(
        week: Range<Date>, stats: WeekStats, records: [PersonalRecord],
        inWeek: [HistoryEntry], history: [HistoryEntry], coachingLogs: [CoachingLog]
    ) -> String {
        if let stall = coachingLogs
            .filter({ ($0.kind == .plateau || $0.kind == .deload) && week.contains($0.date) })
            .max(by: { $0.date < $1.date }) {
            return stall.summary
        }
        if let top = records.first {
            let name = ReportComposer.prettyName(top.exId)
            return records.count == 1
                ? "You set a new personal best on \(name) — the plan is working. Keep the same pattern next week."
                : "\(records.count) new personal bests this week, led by \(name). Progressive overload is doing its job."
        }
        let liftsThisWeek = Set(inWeek.map(\.exId))
        let trending = Dictionary(grouping: history.filter { $0.date < week.upperBound }, by: \.exId)
            .filter { liftsThisWeek.contains($0.key) }
            .compactMap { exId, entries -> (exId: String, pct: Double)? in
                guard let pct = ProgressAggregator.summarize(exId: exId, history: entries).trendPercent,
                      pct > 0 else { return nil }
                return (exId, pct)
            }
            .sorted { $0.pct == $1.pct ? $0.exId < $1.exId : $0.pct > $1.pct }
            .first
        if let trending {
            return "\(ReportComposer.prettyName(trending.exId)) is trending up " +
                   "\(String(format: "%.1f", trending.pct))% — a new best is close."
        }
        return stats.isPerfectWeek
            ? "A perfect week of showing up. Consistency like this is what results are made of."
            : "Consistency beats intensity — aim to hit every scheduled session next week."
    }

    // MARK: - Publishing (the store boundary)

    /// The start of the most recently completed week (the week before `now`'s).
    static func lastCompletedWeekStart(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let thisWeek = StreakEngine.startOfWeek(for: now, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: -7, to: thisWeek)
    }

    /// Whether a report for the week starting `weekStart` already exists among `logs`
    /// (matched on the persisted `weekStart` metric, tolerant of DST-length days).
    static func isPublished(weekStart: Date, in logs: [CoachingLog]) -> Bool {
        let target = weekStart.timeIntervalSinceReferenceDate
        return logs.contains { log in
            log.kind == .weeklyReport &&
            log.payload[metric: MetricKey.weekStart].map { abs($0 - target) < 43_200 } == true
        }
    }

    /// Composes and records last week's report unless it is already published or the
    /// week was idle. Called on app open (MainTabView); idempotent per week. Saves.
    @discardableResult
    static func publishIfDue(
        context: ModelContext, now: Date = Date(), calendar: Calendar = .current
    ) -> CoachingLog? {
        guard let weekStart = lastCompletedWeekStart(now: now, calendar: calendar),
              !isPublished(weekStart: weekStart, in: context.coachingLogs(kind: .weeklyReport))
        else { return nil }

        let profile = context.userProfile()
        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
        guard let report = compose(
            weekStart: weekStart,
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
            .weeklyReport, summary: report.headline, date: now,
            payload: CoachingPayload(metrics: [
                MetricKey.weekStart: weekStart.timeIntervalSinceReferenceDate,
                MetricKey.sets: Double(report.stats.totalSets),
                MetricKey.volumeKg: report.stats.totalVolumeKg,
                MetricKey.daysTrained: Double(report.stats.daysTrained),
                MetricKey.daysScheduled: Double(report.stats.daysScheduled),
                MetricKey.records: Double(report.records.count),
            ]),
            bodyMarkdown: report.markdown
        )
        try? context.save()
        return log
    }

    // MARK: - Rendering

    private static func markdown(
        headline: String, stats: WeekStats, records: [PersonalRecord], note: String,
        bodyweightEntries: [BodyweightEntry], weekEnd: Date, goal: Goal, units: Units
    ) -> String {
        var out = "# \(headline)\n\n"

        out += "## Training\n"
        if stats.daysScheduled > 0 {
            out += "- **\(stats.scheduledDone) of \(stats.daysScheduled)** scheduled workouts completed"
            if stats.isPerfectWeek { out += " — a perfect week" }
            if stats.extraDays > 0 {
                out += " (+\(stats.extraDays) extra session\(stats.extraDays == 1 ? "" : "s"))"
            }
            out += "\n"
        } else {
            out += "- **\(stats.daysTrained)** training day\(stats.daysTrained == 1 ? "" : "s") logged\n"
        }
        out += "- **\(stats.totalSets) set\(stats.totalSets == 1 ? "" : "s")** · " +
               "**\(formatVolume(kg: stats.totalVolumeKg, units: units))** total volume"
        if let previous = stats.previousWeekSets {
            out += " (last week: \(previous) set\(previous == 1 ? "" : "s"))"
        }
        out += "\n"
        // A tonnage nobody can picture is a tonnage nobody remembers.
        if let picture = VolumeNarrator.tonnageSentence(kg: stats.totalVolumeKg, catalog: .shared,
                                                        seed: VolumeNarrator.seed(for: weekEnd)) {
            out += "- \(picture)\n"
        }
        out += "\n"

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

        let weighIns = bodyweightEntries.filter { $0.date < weekEnd }
        if let snapshot = BodyweightTracker.snapshot(entries: weighIns) {
            out += "## Bodyweight\n"
            out += "- **\(Formulas.formatBodyweight(kg: snapshot.currentKg, units: units))**"
            out += rateText(snapshot, units: units)
            out += "\n\n"
        }

        out += "## Coach's note\n\(note)\n\n"
        out += "> \(encouragement(for: goal))\n"
        return out
    }

    private static func rateText(_ snapshot: BodyweightSnapshot, units: Units) -> String {
        guard let rate = snapshot.weeklyRateKg else { return "" }
        let formatted = Formulas.formatBodyweight(kg: abs(rate), units: units)
        switch snapshot.direction {
        case .up:   return " · trending up \(formatted)/week"
        case .down: return " · trending down \(formatted)/week"
        case .flat: return " · holding steady"
        case .none: return ""
        }
    }

    private static func encouragement(for goal: Goal) -> String {
        switch goal {
        case .buildMuscle:
            return "Muscle grows between sessions — eat, sleep, and show up again. See you next week."
        case .loseWeight:
            return "The scale follows the work. Keep the sessions coming and let the weekly average do the talking."
        case .recomp:
            return "Recomposition is slow by design — same lifts, a little better every week. Stay the course."
        case .sport:
            return "Strong athletes are durable athletes. Carry this week's work onto the field."
        }
    }

    /// "Jun 22 – Jun 28" for the week starting `weekStart`.
    private static func rangeText(weekStart: Date, calendar: Calendar) -> String {
        let lastDay = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(weekStart.formatted(style)) – \(lastDay.formatted(style))"
    }

    /// Total volume in the display unit with grouping ("12,431kg"). Exact conversion —
    /// the nearest-5 lb plate rounding would be nonsense on a weekly total.
    private static func formatVolume(kg: Double, units: Units) -> String {
        let value = units == .kg ? kg : kg * 2.20462
        return "\(Int(value.rounded()).formatted(.number.grouping(.automatic)))\(units.label)"
    }
}
