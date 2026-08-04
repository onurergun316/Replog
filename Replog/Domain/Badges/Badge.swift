//
//  Badge.swift
//  Replog
//
//  What a badge is, and the one thing it takes to earn it.
//
//  The criterion is a typed enum with its numbers attached, not a string tag beside a loose
//  threshold. That matters: the thresholds in this file are sessions, days, weeks, kilograms,
//  multiples of bodyweight and counts of distinct things, and a single "threshold: Double"
//  column would let a kilogram be compared against a week without the compiler noticing.
//  Every case here is answerable from `BadgeSnapshot`, so a badge that cannot be evaluated
//  cannot be written down in the first place.
//

import Foundation

/// What earns a badge. Each case carries its own units.
nonisolated enum BadgeCriterion: Hashable, Sendable {
    /// Fully completed workouts, lifetime.
    case workouts(Int)
    /// Consecutive calendar days with a completed workout.
    case dayStreak(Int)
    /// Consecutive weeks in which every scheduled day was trained.
    case weekStreak(Int)
    /// Weeks, not necessarily consecutive, where every scheduled day was trained.
    case perfectWeeks(Int)

    /// Sessions completed inside the first `days` after the very first one.
    case earlyStart(sessions: Int, withinDays: Int)

    /// Lifetime count of sessions in which some lift beat its own best estimated 1RM.
    case personalBests(Int)
    /// The most lifts that set a best in a single session.
    case bestsInOneSession(Int)
    /// Best estimated 1RM for a movement pattern, as a multiple of bodyweight.
    case bodyweightMultiple(pattern: StrengthPattern, times: Double)

    /// Lifetime tonnage: weight times reps, bodyweight movements credited.
    case tonnage(Double)
    /// The heaviest single session's tonnage.
    case sessionTonnage(Double)
    case sets(Int)
    case reps(Int)

    /// Distinct catalog entries touched, lifetime.
    case distinctExercises(Int)
    case distinctMuscles(Int)
    case distinctEquipment(Int)
    case distinctCategories(Int)
    /// Distinct compound movements, so exploring is not satisfied by ten curl variations.
    case distinctCompounds(Int)

    /// Sessions started before `hour`, or at/after it.
    case sessionsBefore(hour: Int, count: Int)
    case sessionsAfter(hour: Int, count: Int)
    /// Trained on every day of the week at least once, over any span.
    case everyWeekday
    /// Sessions on a Saturday or Sunday.
    case weekendSessions(Int)
    /// One session covering low, middle and high rep ranges.
    case repRangeSweep
    /// Push and pull tonnage within `withinPercent` of each other, once there is enough
    /// work logged for the ratio to mean anything.
    case pushPullBalance(withinPercent: Double, minTonnage: Double)

    /// Came back and completed a workout after a gap of at least this many days.
    case comeback(afterDays: Int)
    /// Set a best on a movement untouched for at least this many days.
    case dormantBest(afterDays: Int)
    /// Distinct calendar months containing at least one completed workout.
    case monthsActive(Int)
    /// A single session lasting at least this long.
    case sessionMinutes(Int)

    case bodyweightCheckIns(Int)
    case readinessCheckIns(Int)
    case customExercises(Int)
    case plansBuilt(Int)
}

/// Visual weight. Escalates with a ladder so the board reads as a progression.
nonisolated enum BadgeTier: String, Codable, Sendable, CaseIterable {
    case bronze, silver, gold, jewel, elite
}

/// The outline a medal is struck in. Varied across a family so a grid does not read as
/// one shape repeated fifty times.
nonisolated enum BadgeShape: String, Codable, Sendable, CaseIterable {
    case circle, oval, rect, triangle, shield, hexagon, diamond, starburst
}

/// The device inside the medal. Shared down one ladder, so a progression is recognisable
/// at a glance even as the shape and tier change.
nonisolated enum BadgeMotif: String, Codable, Sendable, CaseIterable {
    case chevrons, rays, bars, laurel, concentricRings, crossedBars
    case ascendingSteps, flame, wave, grid, orbit, peak
}

/// What a badge belongs to. Families group the board and give the detail sheet a heading.
nonisolated enum BadgeFamily: String, Codable, Sendable, CaseIterable, Identifiable {
    case foundations, rhythm, strength, work, atlas, craft, curiosities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foundations: return "Foundations"
        case .rhythm:      return "Rhythm"
        case .strength:    return "Strength"
        case .work:        return "Work"
        case .atlas:       return "Atlas"
        case .craft:       return "Craft"
        case .curiosities: return "Curiosities"
        }
    }

    var blurb: String {
        switch self {
        case .foundations: return "Every finished session, counted from your first one upward."
        case .rhythm:      return "Showing up on repeat: days in a row and weeks held unbroken."
        case .strength:    return "Beating numbers you set yourself, and the old bodyweight standards."
        case .work:        return "Honest volume. Tonnage, sets and reps that only add up by training."
        case .atlas:       return "How much of the gym you have actually explored."
        case .craft:       return "The judgement side of training: balance, range, and coming back."
        case .curiosities: return "Hidden until they happen. You never chase these; they find you."
        }
    }

    /// Curiosities keep their unlock hidden, which is the whole point of them.
    var revealsCriterionWhenLocked: Bool { self != .curiosities }
}

/// One badge. Definitions are static and live in `BadgeCatalog`.
nonisolated struct Badge: Identifiable, Hashable, Sendable {
    /// Stable id. Persisted on the award, so it must never change once shipped.
    var id: String
    var name: String
    var family: BadgeFamily
    var tier: BadgeTier
    var shape: BadgeShape
    var motif: BadgeMotif
    /// Palette id from `MedalPalette`. A token, not prose.
    var palette: String
    var criterion: BadgeCriterion
    /// Shown while locked: how to get it, without spoiling a curiosity.
    var hint: String
    /// Shown once earned: why this milestone is worth something.
    var meaning: String

    /// Whether the locked card should name the target. Curiosities stay vague.
    var revealsHintWhenLocked: Bool { family.revealsCriterionWhenLocked }
}
