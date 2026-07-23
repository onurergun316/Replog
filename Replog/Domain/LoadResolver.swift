//
//  LoadResolver.swift
//  Replog
//
//  The one place the app decides what a recorded set actually loaded.
//
//  Every tonnage figure used to be a literal `set.w * set.r` in ten separate places,
//  which meant a bodyweight set (stored as 0 kg) was worth nothing everywhere at once.
//  Aggregators now take a resolver instead, so bodyweight credit is applied uniformly.
//
//  Resolved at READ time, never baked into `HistoryEntry`. Three consequences, all
//  deliberate: sessions logged before any of this existed are credited retroactively
//  with no migration, re-tuning the factor table re-values the past automatically, and
//  the stored `e1rm` stops being the source of truth for analytics.
//

import Foundation

/// The athlete's bodyweight as of any date — historical tonnage should be credited at
/// the bodyweight they *were*, not the one they are now.
struct BodyweightResolver {
    /// Ascending by date.
    private let series: [(date: Date, kg: Double)]

    @MainActor
    init(entries: [BodyweightEntry]) {
        series = entries.sorted { $0.date < $1.date }.map { ($0.date, $0.weightKg) }
    }

    /// Explicit series, for tests and previews.
    init(series: [(date: Date, kg: Double)]) {
        self.series = series.sorted { $0.date < $1.date }
    }

    /// The most recent check-in on or before `date`; falls back to the earliest known
    /// weight so sets logged before the first check-in still get credited, and `nil`
    /// only when the athlete has never weighed in.
    func weightKg(at date: Date) -> Double? {
        guard !series.isEmpty else { return nil }
        var best: Double?
        for point in series {
            if point.date <= date { best = point.kg } else { break }
        }
        return best ?? series.first?.kg
    }
}

/// Turns a recorded set into the load and rep-equivalents it really represents.
///
/// The default (`.stored`) reads weight and reps exactly as logged, so a call site that
/// hasn't opted in behaves precisely as it did before this type existed.
struct LoadResolver {
    private let exercise: ((String) -> Exercise?)?
    private let bodyweight: BodyweightResolver?

    /// Weight and reps as stored — the pre-bodyweight reading.
    static let stored = LoadResolver()

    init(exercise: ((String) -> Exercise?)? = nil, bodyweight: BodyweightResolver? = nil) {
        self.exercise = exercise
        self.bodyweight = bodyweight
    }

    /// The production resolver, built from the two things every Progress screen already
    /// has to hand: the catalog and the bodyweight series.
    @MainActor
    static func live(catalog: ExerciseCatalog, bodyweightEntries: [BodyweightEntry]) -> LoadResolver {
        LoadResolver(exercise: { catalog.exercise(id: $0) },
                     bodyweight: BodyweightResolver(entries: bodyweightEntries))
    }

    /// Kilograms this set actually moved: the bodyweight share plus whatever was added,
    /// or simply the stored weight for barbell/machine work.
    func kg(exId: String, set: RecordedSet, on date: Date) -> Double {
        guard let exercise, let bodyweight else { return set.w }
        return BodyweightLoad.effectiveKg(addedKg: set.w,
                                          exercise: exercise(exId),
                                          bodyweightKg: bodyweight.weightKg(at: date))
    }

    /// Reps, except for a timed hold where the stored count is seconds.
    func repEquivalents(exId: String, set: RecordedSet) -> Double {
        guard let exercise else { return Double(set.r) }
        return BodyweightLoad.repEquivalents(reps: set.r, exercise: exercise(exId))
    }

    /// Whether this exercise's logged "reps" are really seconds. Rep-range statistics
    /// have to drop these — a 45-second plank is not a set of 45.
    func isTimedHold(exId: String) -> Bool {
        guard let exercise, let match = exercise(exId) else { return false }
        return BodyweightLoad.isTimedHold(match)
    }

    /// One set's contribution to tonnage.
    func volumeKg(exId: String, set: RecordedSet, on date: Date) -> Double {
        kg(exId: exId, set: set, on: date) * repEquivalents(exId: exId, set: set)
    }

    /// A whole history entry's tonnage.
    @MainActor
    func volumeKg(_ entry: HistoryEntry) -> Double {
        entry.sets.reduce(0.0) { $0 + volumeKg(exId: entry.exId, set: $1, on: entry.date) }
    }

    /// The externally-loaded part of an entry's tonnage — plates, dumbbells, a dip belt.
    /// Paired with `bodyweightVolumeKg` it splits a blended total without double-counting.
    @MainActor
    func externalVolumeKg(_ entry: HistoryEntry) -> Double {
        entry.sets.reduce(0.0) { sum, set in
            sum + set.w * repEquivalents(exId: entry.exId, set: set)
        }
    }

    /// The part of an entry's tonnage that came from moving the athlete's own body.
    @MainActor
    func bodyweightVolumeKg(_ entry: HistoryEntry) -> Double {
        max(0, volumeKg(entry) - externalVolumeKg(entry))
    }

    /// The entry's estimated 1RM over *effective* load, which is what finally lets a
    /// pull-up rank against a barbell row. Recomputed rather than read from the stored
    /// `e1rm`, which was written before bodyweight credit existed.
    @MainActor
    func e1rm(_ entry: HistoryEntry) -> Int {
        let top = RecordedSet(w: entry.topW, r: entry.topR)
        let reps = repEquivalents(exId: entry.exId, set: top)
        let kg = kg(exId: entry.exId, set: top, on: entry.date)
        guard reps > 0 else { return 0 }
        return Int(Formulas.e1rm(kg: kg, reps: Int(reps.rounded())).rounded())
    }
}
