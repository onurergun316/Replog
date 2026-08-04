//
//  CoachEngine.swift
//  Replog
//
//  The explainable coach. Pure, deterministic insight generation from the athlete's real
//  data — a finished session, per-lift history, streaks, bodyweight trend, and the active
//  program's progression rules. Every recommendation carries a plain-language REASON derived
//  from the deterministic engines (`ProgressionEngine`, `StallDetector`, `BodyweightTracker`,
//  `StreakEngine`); the LLM may later reword an insight into coach voice (`CoachVoice`) but
//  never invents the decision. The model sees only the finished, reasoned text.
//
//  Output is a priority-sorted `[CoachInsight]`. The post-session debrief shows the lot; the
//  Today "Coach" card shows just the top one, once per day.
//

import Foundation

// MARK: - Insight value types

/// What a coach insight is about. Drives iconography, grouping, and which get recorded.
enum CoachInsightKind: String, Codable, Sendable, CaseIterable {
    case sessionDebrief
    case stallAlert
    case adherenceInsight
    case milestone
    case bodyweightTrend
    case checkInPrompt
    case readinessTrend
    case welcome

    /// Tie-break rank when two insights share a priority (lower surfaces first).
    var sortRank: Int {
        switch self {
        case .stallAlert:       return 0
        case .adherenceInsight: return 1
        case .readinessTrend:   return 2
        case .sessionDebrief:   return 3
        case .milestone:        return 4
        case .bodyweightTrend:  return 5
        case .checkInPrompt:    return 6
        case .welcome:          return 7
        }
    }
}

/// How urgently an insight wants attention. `Comparable` so insights sort by importance.
enum CoachPriority: Int, Comparable, Sendable {
    case low = 0, normal = 1, high = 2, urgent = 3
    static func < (a: CoachPriority, b: CoachPriority) -> Bool { a.rawValue < b.rawValue }
}

/// One coach insight: a titled, reasoned note the athlete reads. `body` is always the
/// explainable reason; `exId`/`metrics`/`tags` are the optional structured payload.
struct CoachInsight: Equatable, Sendable, Identifiable {
    var kind: CoachInsightKind
    var priority: CoachPriority
    var title: String
    var body: String
    var exId: String?
    var metrics: [String: Double]
    var tags: [String]

    var id: String { "\(kind.rawValue)-\(exId ?? "-")-\(title)" }

    init(kind: CoachInsightKind, priority: CoachPriority, title: String, body: String,
         exId: String? = nil, metrics: [String: Double] = [:], tags: [String] = []) {
        self.kind = kind
        self.priority = priority
        self.title = title
        self.body = body
        self.exId = exId
        self.metrics = metrics
        self.tags = tags
    }
}

// MARK: - Engine inputs

/// One lift's outcome in a just-finished session.
struct FinishedLift: Equatable, Sendable {
    var exId: String
    var name: String
    var topWeightKg: Double
    var topReps: Int
    var e1rm: Int
    /// True when this session's top e1RM beat every prior session's.
    var isPR: Bool
    /// Total weight × reps completed for this lift this session.
    var volumeKg: Double
}

/// A just-finished session, distilled for the debrief.
struct SessionOutcome: Equatable, Sendable {
    var lifts: [FinishedLift]
    var totalVolumeKg: Double
    /// This workout's total volume last time it was performed, if known.
    var previousTotalVolumeKg: Double?
    var isFullyComplete: Bool

    var prCount: Int { lifts.filter(\.isPR).count }
}

/// Everything the coach reasons about. Built from the store by `CoachContextBuilder`, but a
/// plain value type so tests construct any persona directly.
struct CoachContext: Sendable {
    var goal: Goal
    var units: Units
    var now: Date
    /// Present immediately after a Finish (drives the debrief); nil for the Today card.
    var justFinished: SessionOutcome?
    /// Recent history per exercise (for stall detection + the next-session recommendation).
    var historyByExercise: [String: [HistoryEntry]]
    /// exId → display name, for readable insight text.
    var exerciseNames: [String: String]
    var workoutStreak: Int
    var weekStreak: Int
    /// A workout is scheduled today.
    var hasScheduledWorkoutToday: Bool
    /// Today's scheduled workout is already done.
    var completedScheduledToday: Bool
    var bodyweight: BodyweightSnapshot?
    var bodyweightCheckInDue: Bool
    /// The active program's `progression.deload` rule, when program-driven.
    var programDeloadRule: String?
    /// Whole program weeks completed (for a program-week milestone), if derivable.
    var programWeeksCompleted: Int?
    /// A recurring readiness pattern across the week (e.g. three low-sleep days), if any.
    var readinessPattern: ReadinessPattern?
    /// True when the athlete has no logged history at all.
    var isFreshUser: Bool
    /// Reference masses used to turn a tonnage into a picture. Injectable so tests can
    /// pin the comparison, and empty in a test simply means no picture is added.
    var comparisons: ComparisonCatalog

    init(goal: Goal = .buildMuscle, units: Units = .kg, now: Date = Date(),
         justFinished: SessionOutcome? = nil,
         historyByExercise: [String: [HistoryEntry]] = [:],
         exerciseNames: [String: String] = [:],
         workoutStreak: Int = 0, weekStreak: Int = 0,
         hasScheduledWorkoutToday: Bool = false, completedScheduledToday: Bool = false,
         bodyweight: BodyweightSnapshot? = nil, bodyweightCheckInDue: Bool = false,
         programDeloadRule: String? = nil, programWeeksCompleted: Int? = nil,
         readinessPattern: ReadinessPattern? = nil,
         isFreshUser: Bool = false,
         comparisons: ComparisonCatalog = .shared) {
        self.comparisons = comparisons
        self.goal = goal
        self.units = units
        self.now = now
        self.justFinished = justFinished
        self.historyByExercise = historyByExercise
        self.exerciseNames = exerciseNames
        self.workoutStreak = workoutStreak
        self.weekStreak = weekStreak
        self.hasScheduledWorkoutToday = hasScheduledWorkoutToday
        self.completedScheduledToday = completedScheduledToday
        self.bodyweight = bodyweight
        self.bodyweightCheckInDue = bodyweightCheckInDue
        self.programDeloadRule = programDeloadRule
        self.programWeeksCompleted = programWeeksCompleted
        self.readinessPattern = readinessPattern
        self.isFreshUser = isFreshUser
    }
}

// MARK: - Engine

enum CoachEngine {

    /// Streak values that read as a milestone worth celebrating.
    static let streakMilestones: Set<Int> = [3, 5, 7, 10, 14, 21, 30, 50, 75, 100]

    /// All applicable insights, highest priority first (ties broken by `kind.sortRank`).
    static func insights(_ ctx: CoachContext) -> [CoachInsight] {
        var out: [CoachInsight] = []
        out += debriefInsights(ctx)
        out += stallInsights(ctx)
        out += adherenceInsights(ctx)
        out += streakMilestoneInsights(ctx)
        out += bodyweightInsights(ctx)
        out += readinessInsights(ctx)
        out += checkInInsights(ctx)

        if out.isEmpty && ctx.isFreshUser {
            out.append(CoachInsight(
                kind: .welcome, priority: .low,
                title: "Welcome to Replog",
                body: "Log your first workout and I'll start tailoring your training and coaching to how you actually progress."))
        }
        return out.sorted { lhs, rhs in
            lhs.priority != rhs.priority
                ? lhs.priority > rhs.priority
                : lhs.kind.sortRank < rhs.kind.sortRank
        }
    }

    /// The single insight the Today card should show (top priority), if any.
    static func topInsight(_ ctx: CoachContext) -> CoachInsight? { insights(ctx).first }

    // MARK: Debrief (post-session)

    private static func debriefInsights(_ ctx: CoachContext) -> [CoachInsight] {
        guard let outcome = ctx.justFinished, !outcome.lifts.isEmpty else { return [] }
        var out: [CoachInsight] = []

        // PR milestone(s) — celebrate the biggest lift's new best explicitly.
        if outcome.prCount > 0 {
            let prLifts = outcome.lifts.filter(\.isPR)
            let names = prLifts.prefix(3).map(\.name).joined(separator: ", ")
            out.append(CoachInsight(
                kind: .milestone, priority: .high,
                title: outcome.prCount == 1 ? "New personal best!" : "\(outcome.prCount) new personal bests!",
                body: "You hit a new estimated-1RM best on \(names). That's real, measurable progress — logged and banked.",
                metrics: ["prCount": Double(outcome.prCount)],
                tags: prLifts.map(\.exId)))
        }

        // The debrief itself: volume vs last time + the next-session recommendation & its reason.
        let volumeLine = volumeSentence(outcome, units: ctx.units, comparisons: ctx.comparisons,
                                        seed: VolumeNarrator.seed(for: ctx.now))
        let nextLine = nextSessionSentence(ctx, outcome: outcome)
        let title = outcome.isFullyComplete ? "Session complete" : "Progress saved"
        var body = "\(volumeLine)"
        if !nextLine.isEmpty { body += " \(nextLine)" }

        out.append(CoachInsight(
            kind: .sessionDebrief, priority: .normal,
            title: title, body: body,
            metrics: ["totalVolumeKg": outcome.totalVolumeKg,
                      "prCount": Double(outcome.prCount)]))
        return out
    }

    /// The session's tonnage, then a picture of it. A kilogram total is accurate and
    /// forgettable; "that is three Smart cars" is the same fact with a handle on it. The
    /// comparison is dropped silently when nothing in the library fits the total.
    private static func volumeSentence(_ outcome: SessionOutcome, units: Units,
                                       comparisons: ComparisonCatalog, seed: Int) -> String {
        let total = Formulas.formatWeight(kg: outcome.totalVolumeKg, units: units)
        let picture = VolumeNarrator.tonnageSentence(kg: outcome.totalVolumeKg,
                                                     catalog: comparisons, seed: seed)
            .map { " \($0)" } ?? ""

        guard let prev = outcome.previousTotalVolumeKg, prev > 0 else {
            return "You moved \(total) of total volume across \(outcome.lifts.count) exercises.\(picture)"
        }
        let pct = (outcome.totalVolumeKg - prev) / prev * 100
        if pct >= 1 {
            return "Total volume \(total) — up \(Int(pct.rounded()))% on your last time through this workout.\(picture)"
        } else if pct <= -1 {
            return "Total volume \(total) — down \(Int((-pct).rounded()))% vs last time (an easier day is fine; recovery counts).\(picture)"
        }
        return "Total volume \(total) — right in line with last time.\(picture)"
    }

    /// The next-session recommendation for the session's key lift, with the engine's reason.
    private static func nextSessionSentence(_ ctx: CoachContext, outcome: SessionOutcome) -> String {
        // The key lift: a PR lift if any, else the highest-volume lift.
        let key = outcome.lifts.filter(\.isPR).first
            ?? outcome.lifts.max(by: { $0.volumeKg < $1.volumeKg })
        guard let key,
              let history = ctx.historyByExercise[key.exId],
              let rec = ProgressionEngine.recommend(exId: key.exId, history: history,
                                                    goal: ctx.goal, units: ctx.units) else { return "" }
        return "Next time on \(key.name): \(rec.reason)"
    }

    // MARK: Stall alerts

    private static func stallInsights(_ ctx: CoachContext) -> [CoachInsight] {
        // Only consider lifts touched in the finished session, else recent history keys.
        let exIds = ctx.justFinished.map { $0.lifts.map(\.exId) }
            ?? Array(ctx.historyByExercise.keys)
        var out: [CoachInsight] = []
        for exId in exIds {
            guard let history = ctx.historyByExercise[exId],
                  let stall = StallDetector.detect(exId: exId, history: history) else { continue }
            let name = ctx.exerciseNames[exId] ?? "This lift"
            out.append(stallInsight(stall, name: name, ctx: ctx))
        }
        // At most one stall alert surfaces at a time (the longest-running).
        return out.sorted { ($0.metrics["sessionsStalled"] ?? 0) > ($1.metrics["sessionsStalled"] ?? 0) }
            .prefix(1).map { $0 }
    }

    private static func stallInsight(_ stall: StallDetection, name: String, ctx: CoachContext) -> CoachInsight {
        let verb = stall.trend == .regression ? "trending down" : "stuck"
        let reason = "\(name) has been \(verb) for \(stall.sessionsStalled) sessions"
        let suggestion: String
        switch stall.response {
        case .deload:
            // Prefer the program's own deload rule when program-driven, else compute ~10% off.
            if let rule = ctx.programDeloadRule, !rule.isEmpty {
                suggestion = "deload per your program: \(rule)"
            } else {
                let target = ProgressionEngine.deloadWeight(
                    fromKg: stall.lastTopWeightKg, stepKg: Formulas.weightStepKg(units: ctx.units))
                suggestion = "deload to \(Formulas.formatWeight(kg: target, units: ctx.units)) and rebuild"
            }
        case .swapExercise:
            suggestion = stall.lastTopWeightKg == 0
                ? "swap in a harder variation to change the stimulus"
                : "a deload didn't unstick it — swap in a similar movement"
        }
        return CoachInsight(
            kind: .stallAlert, priority: .high,
            title: "\(name) has plateaued",
            body: "\(reason) — \(suggestion).",
            exId: stall.exId,
            metrics: ["sessionsStalled": Double(stall.sessionsStalled),
                      "lastE1RM": Double(stall.lastE1RM)],
            tags: [stall.response.rawValue, stall.trend.rawValue])
    }

    // MARK: Adherence

    private static func adherenceInsights(_ ctx: CoachContext) -> [CoachInsight] {
        // Only a risk when a scheduled workout today is still undone and a streak is on the line.
        guard ctx.hasScheduledWorkoutToday, !ctx.completedScheduledToday, ctx.justFinished == nil else { return [] }
        guard ctx.workoutStreak > 0 else {
            return [CoachInsight(
                kind: .adherenceInsight, priority: .normal,
                title: "Today's the day",
                body: "You've got a workout scheduled today. Knocking it out now keeps your momentum building.")]
        }
        return [CoachInsight(
            kind: .adherenceInsight, priority: .high,
            title: "Keep your streak alive",
            body: "Your \(ctx.workoutStreak)-day streak is on the line — today's session is still waiting. A quick session keeps it going.",
            metrics: ["workoutStreak": Double(ctx.workoutStreak)])]
    }

    // MARK: Streak & program milestones

    private static func streakMilestoneInsights(_ ctx: CoachContext) -> [CoachInsight] {
        var out: [CoachInsight] = []
        if streakMilestones.contains(ctx.workoutStreak) {
            out.append(CoachInsight(
                kind: .milestone, priority: .normal,
                title: "\(ctx.workoutStreak)-day streak!",
                body: "\(ctx.workoutStreak) training days in a row. Consistency like this is what actually drives long-term results.",
                metrics: ["workoutStreak": Double(ctx.workoutStreak)]))
        }
        if let weeks = ctx.programWeeksCompleted, weeks > 0, weeks % 4 == 0 {
            out.append(CoachInsight(
                kind: .milestone, priority: .normal,
                title: "\(weeks) weeks of your program done",
                body: "You've completed \(weeks) weeks of your program — a great point to reflect on how the loads have climbed.",
                metrics: ["programWeeks": Double(weeks)]))
        }
        return out
    }

    // MARK: Bodyweight

    private static func bodyweightInsights(_ ctx: CoachContext) -> [CoachInsight] {
        guard let bw = ctx.bodyweight, let rate = bw.weeklyRateKg,
              bw.direction == .up || bw.direction == .down else { return [] }
        let perWeek = Formulas.formatWeight(kg: abs(rate), units: ctx.units)
        let dir = bw.direction == .up ? "up" : "down"
        let favor = BodyweightTracker.isFavorable(bw.direction, for: ctx.goal)
        let tail: String
        switch favor {
        case .some(true):  tail = "That's the right direction for your goal — keep it steady."
        case .some(false): tail = "That's against your goal — worth a look at intake and recovery."
        case .none:        tail = "Steady, gradual change is what you want."
        }
        return [CoachInsight(
            kind: .bodyweightTrend, priority: .low,
            title: "Bodyweight trending \(dir)",
            body: "You're trending \(dir) about \(perWeek)/week over the last month. \(tail)",
            metrics: ["weeklyRateKg": rate])]
    }

    // MARK: Readiness pattern

    private static func readinessInsights(_ ctx: CoachContext) -> [CoachInsight] {
        guard let pattern = ctx.readinessPattern, ctx.justFinished == nil else { return [] }
        let (what, advice): (String, String)
        switch pattern {
        case .lowSleep(let days):
            what = "\(days) low-sleep days this week"
            advice = "Sleep is where you actually adapt — protect it, and keep sessions honest on tired days."
        case .highSoreness(let days):
            what = "high soreness on \(days) days this week"
            advice = "Persistent soreness can mean you're outrunning recovery — an easier day or extra rest is smart."
        case .highStress(let days):
            what = "high stress on \(days) days this week"
            advice = "Life stress and training stress share a budget — dial intensity to what you can recover from."
        }
        return [CoachInsight(
            kind: .readinessTrend, priority: .normal,
            title: "Readiness check",
            body: "You've logged \(what). \(advice)",
            metrics: ["patternDays": Double(pattern.days)])]
    }

    // MARK: Check-in prompt

    private static func checkInInsights(_ ctx: CoachContext) -> [CoachInsight] {
        guard ctx.bodyweightCheckInDue, ctx.justFinished == nil else { return [] }
        return [CoachInsight(
            kind: .checkInPrompt, priority: .low,
            title: "Time for a weigh-in",
            body: "It's been a week since your last bodyweight check-in. A quick weigh-in keeps your trend line honest.")]
    }
}
