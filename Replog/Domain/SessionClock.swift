//
//  SessionClock.swift
//  Replog
//
//  How long a session actually takes.
//
//  A program's `sessionMinutes` is a number a human typed into a JSON file, and nothing ever
//  checked it. Every 3-day program in the bundled library prescribes LESS work than it
//  claims — `ppl_3d` declares 65 minutes and prescribes about 53; `weekly_lp_intermediate_3d`
//  declares 75 and prescribes 28. An athlete who set aside 80 minutes was handed 17 sets and
//  told it was their 80-minute session, because both the matcher and the result screen were
//  quoting numbers nobody had measured: the program's claim, and the athlete's own request.
//
//  This measures the session instead — from its actual sets, reps, prescribed rest, and the
//  fixed costs a stopwatch would catch: finding the rack, changing plates, warming up.
//
//  Pure, so the whole model is testable without a store, a catalog or a device. The
//  components are kept separate rather than summed into one number so a caller (and a test)
//  can see WHERE a session's time goes, which is what makes the estimate arguable rather
//  than magic.
//

import Foundation

/// A session's cost in time, itemised.
nonisolated struct SessionDuration: Equatable, Sendable {
    /// Time under the bar: sets × the time one set takes.
    var workSeconds: Double = 0
    /// Time between sets, at the rest each slot prescribes.
    var restSeconds: Double = 0
    /// Finding the equipment, loading it, walking to the next station.
    var setupSeconds: Double = 0
    /// The general warm-up and ramp sets before the first working set.
    var warmUpSeconds: Double = 0

    var totalSeconds: Double { workSeconds + restSeconds + setupSeconds + warmUpSeconds }
    var minutes: Double { totalSeconds / 60 }
    /// Minutes as a person would say them, to the nearest 5.
    var roundedMinutes: Int { max(5, Int((minutes / 5).rounded()) * 5) }
}

enum SessionClock {

    // MARK: - Constants
    //
    // Every one of these is a claim about what training looks like, so each is named and
    // says what it represents rather than appearing as a number in a formula.

    /// A rep on a loaded compound: brace, descend, drive, reset.
    static let secondsPerCompoundRep: Double = 3.5
    /// A rep on everything else. An isolation rep is not a squat rep.
    static let secondsPerRep: Double = 2.5
    /// Finding a loaded station and setting it up — bar, plates, pin, bench angle.
    static let loadedSetupSeconds: Double = 60
    /// Rolling out a mat or picking up a band.
    static let unloadedSetupSeconds: Double = 20
    /// A general warm-up plus ramp sets, when the day opens with heavy compound work.
    static let heavyWarmUpSeconds: Double = 480
    /// A general warm-up when the day is loaded but not heavy.
    static let loadedWarmUpSeconds: Double = 300
    /// Mobility and core work still needs a few minutes to start moving.
    static let lightWarmUpSeconds: Double = 120
    /// Rest a slot gets when it declares none, by what the movement asks of the athlete.
    /// The old flat default made a stretching routine compute at twice its real length.
    static func defaultRest(for pattern: MovementPattern) -> Double {
        switch pattern {
        case .squat, .hinge, .lunge, .horizontalPush, .verticalPush,
             .horizontalPull, .verticalPull, .carry:            return 120
        case .isolationArms, .isolationCalves,
             .isolationGlutes, .isolationShoulders:             return 75
        case .coreBrace, .coreFlexion, .plyometric:             return 60
        case .run, .bike, .rowErg, .swim:                       return 60
        case .stretchStatic, .stretchDynamic, .mobilityDrill:   return 15
        case .other:                                            return 90
        }
    }

    // MARK: - One set

    /// How long one set of `slot` takes.
    static func setSeconds(for slot: ProgramSlot) -> Double {
        let target = RepScheme.parse(reps: slot.reps, pattern: slot.pattern)
        let base: Double
        if target.isTimed {
            base = Double(target.reps)              // already a duration
        } else {
            base = Double(target.reps) * (isCompound(slot.pattern) ? secondsPerCompoundRep : secondsPerRep)
        }
        // A per-side scheme is both sides: the set is not over until the second one is.
        return target.isPerSide ? base * 2 : base
    }

    // MARK: - One day

    /// What one prescribed day costs.
    ///
    /// Rest is counted between sets and between exercises, but NOT after the final set —
    /// the athlete leaves rather than resting one last time.
    static func duration(for day: ProgramDay) -> SessionDuration {
        var duration = SessionDuration()
        guard !day.slots.isEmpty else { return duration }

        for slot in day.slots {
            let sets = Double(max(1, min(slot.sets, 8)))
            let rest = slot.restSeconds.map(Double.init) ?? defaultRest(for: slot.pattern)
            duration.workSeconds += sets * setSeconds(for: slot)
            duration.restSeconds += sets * rest
            duration.setupSeconds += isLoaded(slot.pattern) ? loadedSetupSeconds : unloadedSetupSeconds
        }

        // The rest that never happens, at the end of the session.
        if let last = day.slots.last {
            duration.restSeconds -= last.restSeconds.map(Double.init) ?? defaultRest(for: last.pattern)
        }
        duration.restSeconds = max(0, duration.restSeconds)
        duration.warmUpSeconds = warmUp(for: day)
        return duration
    }

    // MARK: - What can honestly be measured

    /// Ways a slot describes work the schema cannot express as sets, reps and rest.
    ///
    /// A long run written as "wk1: 20 min -> +5 min every 2 wks -> wk11: 45 min" is a
    /// twelve-week progression table, and "per variant" is a pointer to prose. Parsed, they
    /// yield a one-rep set and a two-minute session. The answer is not a better guess — it
    /// is knowing that this session cannot be measured, and saying so instead of inventing
    /// a number. Anything unmeasurable falls back to what the program declares.
    private static let inexpressible = [
        "wk", "->", "\u{2192}", "per variant", "as prescribed", "per week", "the test",
        "%", "max", "submaximal", " or ", "km", "mile",
        "amrap", "emom", "circuit", "round", "interval", "medley", "complex", "ladder", "wave",
    ]

    /// Whether a slot's prescription can be expressed as concrete sets, reps and rest.
    static func canMeasure(_ slot: ProgramSlot) -> Bool {
        let reps = slot.reps.lowercased()
        if inexpressible.contains(where: { reps.contains($0) }) { return false }
        // A multiplier ("8x100m") is a set scheme inside the rep string, not a rep count.
        let chars = Array(reps)
        for (i, c) in chars.enumerated() where c == "x" {
            let before = i > 0 ? chars[i - 1] : " "
            let after = i + 1 < chars.count ? chars[i + 1] : " "
            if before.isNumber || after.isNumber { return false }
        }
        return true
    }

    /// A day can be measured when every slot in it can.
    static func canMeasure(_ day: ProgramDay) -> Bool {
        !day.slots.isEmpty && day.slots.allSatisfy { canMeasure($0) }
    }

    /// A program can be measured when every one of its days can.
    static func canMeasure(_ program: WorkoutProgram) -> Bool {
        !program.days.isEmpty && program.days.allSatisfy { canMeasure($0) }
    }

    /// A program's typical session — the mean across its day templates.
    ///
    /// `nil` when the program cannot honestly be measured; the caller falls back to what it
    /// declares rather than quoting an invented figure.
    static func meanDuration(for program: WorkoutProgram) -> SessionDuration? {
        guard canMeasure(program) else { return nil }
        let all = program.days.map { duration(for: $0) }
        let count = Double(all.count)
        return SessionDuration(
            workSeconds: all.reduce(0) { $0 + $1.workSeconds } / count,
            restSeconds: all.reduce(0) { $0 + $1.restSeconds } / count,
            setupSeconds: all.reduce(0) { $0 + $1.setupSeconds } / count,
            warmUpSeconds: all.reduce(0) { $0 + $1.warmUpSeconds } / count
        )
    }

    /// The program's LONGEST day — the one that has to fit the athlete's window.
    static func longestDayMinutes(for program: WorkoutProgram) -> Double? {
        guard canMeasure(program) else { return nil }
        return program.days.map { duration(for: $0).minutes }.max()
    }

    // MARK: - Classification

    /// Multi-joint work under load: the movements that need a ramp and a real rest.
    static func isCompound(_ pattern: MovementPattern) -> Bool {
        switch pattern {
        case .squat, .hinge, .lunge, .horizontalPush, .verticalPush,
             .horizontalPull, .verticalPull, .carry:
            return true
        default:
            return false
        }
    }

    /// Whether the movement involves equipment to find and set up.
    static func isLoaded(_ pattern: MovementPattern) -> Bool {
        switch pattern {
        case .stretchStatic, .stretchDynamic, .mobilityDrill, .coreBrace, .coreFlexion,
             .plyometric, .run, .swim:
            return false
        default:
            return true
        }
    }

    /// Warming up costs what the day demands of the athlete, not a flat allowance.
    private static func warmUp(for day: ProgramDay) -> Double {
        let heavy = day.slots.contains { slot in
            isCompound(slot.pattern)
                && (slot.restSeconds.map(Double.init) ?? defaultRest(for: slot.pattern)) >= 120
        }
        if heavy { return heavyWarmUpSeconds }
        if day.slots.contains(where: { isLoaded($0.pattern) }) { return loadedWarmUpSeconds }
        return day.slots.isEmpty ? 0 : lightWarmUpSeconds
    }
}
