//
//  BadgeEngineTests.swift
//  ReplogTests
//
//  The collection itself has to hold together — unique ids, ladders that escalate, no
//  unreachable rungs, no copy that shames a lapse — and every unlock rule has to be
//  answerable from the snapshot. Both are checked here, because a badge nobody can earn
//  and a badge that fires for everyone are the two ways this feature fails quietly.
//

import Testing
import Foundation
@testable import Replog

struct BadgeEngineTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var now: Date {
        DateComponents(calendar: cal, year: 2026, month: 6, day: 30, hour: 12).date!
    }

    private func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

    private func snapshot(_ configure: (inout BadgeSnapshot) -> Void = { _ in }) -> BadgeSnapshot {
        var s = BadgeSnapshot(now: now, calendar: cal)
        configure(&s)
        return s
    }

    // MARK: - The collection holds together

    @Test func theBriefIsMet() {
        // The owner asked for at least fifty badges.
        #expect(BadgeCatalog.all.count >= 50)
    }

    @Test func idsAreUniqueAndStable() {
        let ids = BadgeCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate badge id")
        #expect(ids.allSatisfy { !$0.isEmpty })
        // Every id resolves back, which is what an award row depends on.
        #expect(ids.allSatisfy { BadgeCatalog.badge(id: $0) != nil })
    }

    @Test func namesAreShortAndFreeOfEmoji() {
        for badge in BadgeCatalog.all {
            #expect(badge.name.count <= 22, "\(badge.id) name is too long for a tile")
            #expect(!badge.name.isEmpty)
            #expect(badge.name.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation == false },
                    "\(badge.id) contains an emoji")
        }
    }

    @Test func everyBadgeExplainsItselfBothWays() {
        for badge in BadgeCatalog.all {
            #expect(!badge.hint.isEmpty, "\(badge.id) has no locked hint")
            #expect(!badge.meaning.isEmpty, "\(badge.id) has no earned meaning")
            // The meaning is the reward for earning it, so it should be a real sentence.
            #expect(badge.meaning.count > 40, "\(badge.id) meaning is too thin to be worth reading")
        }
    }

    @Test func everyPaletteResolves() {
        for badge in BadgeCatalog.all {
            #expect(MedalPalettes.hex[badge.palette] != nil,
                    "\(badge.id) names a palette that does not exist: \(badge.palette)")
        }
        // Every palette is a real three-colour hex triple, so no medal renders as a
        // silently-substituted fallback.
        for (id, triple) in MedalPalettes.hex {
            for hex in [triple.body, triple.accent, triple.detail] {
                let digits = String(hex.dropFirst())
                let wellFormed = hex.count == 7 && hex.hasPrefix("#")
                    && digits.allSatisfy { $0.isHexDigit }
                #expect(wellFormed, "\(id) has a malformed hex: \(hex)")
            }
        }
    }

    @Test func theBoardIsVisuallyVaried() {
        // Every family should use more than one shape, or the grid reads as one shape
        // repeated and the medals stop being distinguishable at a glance.
        for family in BadgeFamily.allCases {
            let badges = BadgeCatalog.badges(in: family)
            guard badges.count > 2 else { continue }
            #expect(Set(badges.map(\.shape)).count > 1, "\(family.rawValue) is all one shape")
        }
        // And the collection as a whole should use most of the vocabulary it defines.
        #expect(Set(BadgeCatalog.all.map(\.shape)).count >= 6)
        #expect(Set(BadgeCatalog.all.map(\.motif)).count >= 8)
        #expect(Set(BadgeCatalog.all.map(\.palette)).count >= 15)
    }

    @Test func everyFamilyHasBadges() {
        for family in BadgeFamily.allCases {
            #expect(!BadgeCatalog.badges(in: family).isEmpty, "\(family.rawValue) is empty")
        }
    }

    @Test func theOwnersRequestedBadgesAllExist() {
        // Explicitly asked for: a first workout, a 3-session streak, a 7-session streak,
        // a first personal best, a second personal best, and a 10-session streak.
        let required: [BadgeCriterion] = [
            .workouts(1), .dayStreak(3), .dayStreak(7),
            .personalBests(1), .personalBests(2), .dayStreak(10),
        ]
        for criterion in required {
            #expect(BadgeCatalog.all.contains { $0.criterion == criterion },
                    "no badge for \(criterion)")
        }
    }

    @Test func ladderRungsEscalateInTier() {
        // Within a motif, a bigger number must never carry a lower tier: a ladder that
        // goes gold then silver reads as broken.
        func rank(_ tier: BadgeTier) -> Int {
            BadgeTier.allCases.firstIndex(of: tier) ?? 0
        }
        let workouts = BadgeCatalog.all.compactMap { badge -> (count: Int, tier: BadgeTier)? in
            guard case .workouts(let n) = badge.criterion else { return nil }
            return (n, badge.tier)
        }.sorted { $0.count < $1.count }
        #expect(workouts.count >= 5, "the workout ladder is too short to be a ladder")
        for (lower, higher) in zip(workouts, workouts.dropFirst()) {
            #expect(rank(lower.tier) <= rank(higher.tier),
                    "workout ladder tier regresses at \(higher.count)")
        }
    }

    @Test func nothingIsUnreachableAndNothingIsFree() {
        // A snapshot of a genuinely dedicated multi-year athlete should earn everything;
        // an empty one should earn nothing at all.
        #expect(BadgeEngine.earned(in: snapshot()).isEmpty)

        var maxed = snapshot()
        maxed.totalWorkouts = 900
        maxed.doneDates = (0..<900).map { daysAgo($0) }
        maxed.dayStreak = 400
        maxed.weekStreak = 60
        maxed.perfectWeeks = 60
        maxed.personalBestTotal = 400
        maxed.tonnageKg = 3_000_000
        maxed.setTotal = 12_000
        maxed.repTotal = 120_000
        maxed.pushTonnageKg = 500_000
        maxed.pullTonnageKg = 500_000
        maxed.bestLowerRatio = 2.5
        maxed.bestPushRatio = 1.4
        maxed.bestPullRatio = 1.5
        maxed.distinctExercises = 140
        maxed.distinctMuscles = 16
        maxed.distinctEquipment = 9
        maxed.distinctCategories = 6
        maxed.distinctCompounds = 40
        maxed.bodyweightCheckIns = 60
        maxed.readinessCheckIns = 40
        maxed.customExercises = 8
        maxed.plansBuilt = 6
        maxed.longestReturnGapDays = 90
        maxed.longestDormantBestDays = 200
        // Early sessions and late ones, so the time-of-day curiosities are reachable too.
        maxed.sessions = (0..<40).map { index in
            BadgeSession(date: cal.date(bySettingHour: 5, minute: 0, second: 0, of: daysAgo(index))!,
                         tonnageKg: 35_000, setCount: 30, repCount: 300,
                         durationSeconds: 7200, personalBests: 5,
                         hitLowReps: true, hitMidReps: true, hitHighReps: true)
        } + (0..<30).map { index in
            BadgeSession(date: cal.date(bySettingHour: 23, minute: 0, second: 0, of: daysAgo(index + 100))!,
                         tonnageKg: 9_000, setCount: 20, repCount: 200, personalBests: 1)
        }

        let earned = BadgeEngine.earned(in: maxed)
        let missing = Set(BadgeCatalog.all.map(\.id)).subtracting(earned.map(\.id))
        #expect(missing.isEmpty, "unreachable badges: \(missing.sorted())")
    }

    // MARK: - Individual rules

    @Test func aLadderCountsUp() {
        let s = snapshot { $0.totalWorkouts = 7 }
        #expect(BadgeEngine.isMet(.workouts(5), in: s))
        #expect(!BadgeEngine.isMet(.workouts(10), in: s))
        let progress = BadgeEngine.progress(.workouts(10), in: s)
        #expect(progress.label == "7 / 10")
        #expect(abs(progress.fraction - 0.7) < 0.0001)
    }

    @Test func aBinaryRuleIsNeverPartlyDone() {
        let s = snapshot {
            $0.sessions = [BadgeSession(date: now, hitLowReps: true, hitMidReps: true)]
        }
        let progress = BadgeEngine.progress(.repRangeSweep, in: s)
        #expect(progress.isBinary)
        #expect(progress.fraction == 0)      // not "two thirds of the way to a sweep"
        #expect(progress.label.isEmpty)
    }

    @Test func aRepRangeSweepNeedsAllThreeInOneSession() {
        // Spread across two sessions is not a sweep.
        let split = snapshot {
            $0.sessions = [BadgeSession(date: now, hitLowReps: true, hitMidReps: true),
                           BadgeSession(date: now, hitHighReps: true)]
        }
        #expect(!BadgeEngine.isMet(.repRangeSweep, in: split))

        let together = snapshot {
            $0.sessions = [BadgeSession(date: now, hitLowReps: true, hitMidReps: true, hitHighReps: true)]
        }
        #expect(BadgeEngine.isMet(.repRangeSweep, in: together))
    }

    @Test func balanceNeedsRealWorkOnBothSides() {
        // Even, but almost nothing logged: not a claim worth making.
        let thin = snapshot { $0.pushTonnageKg = 100; $0.pullTonnageKg = 100 }
        #expect(!BadgeEngine.isMet(.pushPullBalance(withinPercent: 20, minTonnage: 5_000), in: thin))

        let lopsided = snapshot { $0.pushTonnageKg = 40_000; $0.pullTonnageKg = 6_000 }
        #expect(!BadgeEngine.isMet(.pushPullBalance(withinPercent: 20, minTonnage: 5_000), in: lopsided))

        let even = snapshot { $0.pushTonnageKg = 20_000; $0.pullTonnageKg = 18_000 }
        #expect(BadgeEngine.isMet(.pushPullBalance(withinPercent: 20, minTonnage: 5_000), in: even))
    }

    @Test func timeOfDayReadsTheSessionStart() {
        let s = snapshot {
            $0.sessions = [
                BadgeSession(date: cal.date(bySettingHour: 5, minute: 30, second: 0, of: now)!),
                BadgeSession(date: cal.date(bySettingHour: 5, minute: 50, second: 0, of: now)!),
                BadgeSession(date: cal.date(bySettingHour: 18, minute: 0, second: 0, of: now)!),
                BadgeSession(date: cal.date(bySettingHour: 23, minute: 0, second: 0, of: now)!),
            ]
        }
        #expect(s.sessions(startedBefore: 6) == 2)
        #expect(s.sessions(startedAtOrAfter: 22) == 1)
    }

    @Test func earlyStartLooksOnlyAtTheFirstWeek() {
        // Three sessions, but spread over a month rather than packed into week one.
        let spread = snapshot { $0.doneDates = [daysAgo(60), daysAgo(40), daysAgo(35)] }
        #expect(!BadgeEngine.isMet(.earlyStart(sessions: 3, withinDays: 7), in: spread))

        let packed = snapshot { $0.doneDates = [daysAgo(60), daysAgo(58), daysAgo(55)] }
        #expect(BadgeEngine.isMet(.earlyStart(sessions: 3, withinDays: 7), in: packed))
    }

    @Test func aRelativeStrengthStandardIsPerMovementPattern() {
        let s = snapshot { $0.bestLowerRatio = 1.6; $0.bestPushRatio = 0.8 }
        #expect(BadgeEngine.isMet(.bodyweightMultiple(pattern: .lowerCompound, times: 1.5), in: s))
        #expect(!BadgeEngine.isMet(.bodyweightMultiple(pattern: .lowerCompound, times: 2.0), in: s))
        // A heavy squat does not hand you the pressing standard.
        #expect(!BadgeEngine.isMet(.bodyweightMultiple(pattern: .upperPush, times: 1.0), in: s))
    }

    @Test func everyWeekdayNeedsAllSeven() {
        let sixDays = snapshot { $0.doneDates = (0..<6).map { daysAgo($0) } }
        #expect(!BadgeEngine.isMet(.everyWeekday, in: sixDays))
        let sevenDays = snapshot { $0.doneDates = (0..<7).map { daysAgo($0) } }
        #expect(BadgeEngine.isMet(.everyWeekday, in: sevenDays))
    }

    @Test func monthsActiveCountsDistinctMonths() {
        let s = snapshot {
            $0.doneDates = [
                DateComponents(calendar: cal, year: 2026, month: 1, day: 5).date!,
                DateComponents(calendar: cal, year: 2026, month: 1, day: 20).date!,
                DateComponents(calendar: cal, year: 2026, month: 3, day: 2).date!,
            ]
        }
        #expect(s.monthsActive == 2)
    }

    // `BadgeAwarding` is MainActor-isolated by the project's default isolation, so this
    // case has to be too — the rest of the suite only touches nonisolated types.
    @MainActor
    @Test func aComebackIsAGapThatWasFollowedByTraining() {
        // An open gap is not a comeback: the athlete has not come back yet.
        let dates = [daysAgo(100), daysAgo(80), daysAgo(1)]
        #expect(BadgeAwarding.longestReturnGap(doneDates: dates, calendar: cal) == 79)
        // A single training day has no gap at all.
        #expect(BadgeAwarding.longestReturnGap(doneDates: [daysAgo(3)], calendar: cal) == 0)
        #expect(BadgeAwarding.longestReturnGap(doneDates: [], calendar: cal) == 0)
    }

    // MARK: - What to show next

    @Test func upNextOffersTheNearestReachableRungs() {
        let s = snapshot { $0.totalWorkouts = 9; $0.personalBestTotal = 1 }
        let next = BadgeEngine.upNext(in: s, limit: 3)

        #expect(!next.isEmpty)
        // Nothing already earned, and nothing untouched.
        #expect(next.allSatisfy { !BadgeEngine.isMet($0.criterion, in: s) })
        #expect(next.allSatisfy { BadgeEngine.progress($0.criterion, in: s).fraction > 0 })
        // Ten workouts at nine done is the closest thing there is.
        #expect(next.first?.id == "tenLogged")
    }

    @Test func upNextNeverSpoilsACuriosity() {
        var s = snapshot()
        s.sessions = [BadgeSession(date: cal.date(bySettingHour: 5, minute: 0, second: 0, of: now)!)]
        #expect(BadgeEngine.upNext(in: s, limit: 20).allSatisfy { $0.family != .curiosities })
    }

    @Test func aCuriosityKeepsItsSecretWhileLocked() {
        for badge in BadgeCatalog.badges(in: .curiosities) {
            #expect(!badge.revealsHintWhenLocked)
        }
        for badge in BadgeCatalog.all where badge.family != .curiosities {
            #expect(badge.revealsHintWhenLocked)
        }
    }
}
