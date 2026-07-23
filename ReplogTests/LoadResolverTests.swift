//
//  LoadResolverTests.swift
//  ReplogTests
//
//  The single tonnage seam: bodyweight credited at the weight the athlete was on the
//  day, added load layered on top, timed holds counted in rep-equivalents, and the
//  default resolver behaving exactly as the raw stored numbers always did.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct LoadResolverTests {

    private let catalog = ExerciseCatalog.shared

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    /// A resolver over the real catalog with a two-point bodyweight series.
    private func resolver(_ series: [(date: Date, kg: Double)]) -> LoadResolver {
        LoadResolver(exercise: { catalog.exercise(id: $0) },
                     bodyweight: BodyweightResolver(series: series))
    }

    private func entry(_ exId: String, _ sets: [(Double, Int)], on date: Date) -> HistoryEntry {
        let recorded = sets.map { RecordedSet(w: $0.0, r: $0.1) }
        let top = recorded.max { Formulas.e1rm(kg: $0.w, reps: $0.r) < Formulas.e1rm(kg: $1.w, reps: $1.r) }!
        return HistoryEntry(exId: exId, date: date, topW: top.w, topR: top.r,
                            e1rm: Formulas.e1rmRounded(kg: top.w, reps: top.r), sets: recorded)
    }

    // MARK: - Bodyweight as of a date

    @Test func bodyweightUsesTheMostRecentCheckInOnOrBeforeTheDate() {
        let bw = BodyweightResolver(series: [(day(-30), 90), (day(-10), 85), (day(-1), 84)])
        #expect(bw.weightKg(at: day(-20)) == 90)
        #expect(bw.weightKg(at: day(-5)) == 85)
        #expect(bw.weightKg(at: day(0)) == 84)
    }

    @Test func setsLoggedBeforeTheFirstCheckInUseTheEarliestKnownWeight() {
        // Better than crediting nothing: the athlete had a bodyweight, we just met them late.
        let bw = BodyweightResolver(series: [(day(-10), 85)])
        #expect(bw.weightKg(at: day(-40)) == 85)
    }

    @Test func neverWeighedInMeansNoBodyweightCredit() {
        let bw = BodyweightResolver(series: [])
        #expect(bw.weightKg(at: day(0)) == nil)
    }

    @Test func historicalTonnageUsesTheBodyweightOfTheDay() {
        // 0.95 x 90 = 85.5 back then, 0.95 x 80 = 76 now — the same 10 reps are not
        // the same work, and backdated entries must not be re-priced at today's weight.
        let r = resolver([(day(-30), 90), (day(-1), 80)])
        let old = entry("Pullups", [(0, 10)], on: day(-20))
        let recent = entry("Pullups", [(0, 10)], on: day(0))
        #expect(r.volumeKg(old) == 855)
        #expect(r.volumeKg(recent) == 760)
    }

    // MARK: - The default resolver changes nothing

    @Test func storedResolverReadsWeightAndRepsExactlyAsLogged() {
        let r = LoadResolver.stored
        let pullups = entry("Pullups", [(0, 10)], on: day(0))
        let bench = entry("Barbell_Bench_Press_-_Medium_Grip", [(100, 5), (100, 5)], on: day(0))
        // The pre-existing reading: a bodyweight set really was worth zero.
        #expect(r.volumeKg(pullups) == 0)
        #expect(r.volumeKg(bench) == 1000)
        #expect(r.repEquivalents(exId: "Plank", set: RecordedSet(w: 0, r: 30)) == 30)
    }

    // MARK: - Blended totals and their split

    @Test func externalAndBodyweightVolumeSumToTheBlendedTotal() {
        let r = resolver([(day(-1), 80)])
        // Weighted pull-ups: 0.95 x 80 = 76 of body, plus a 10 kg belt, 8 reps.
        let e = entry("Pullups", [(10, 8)], on: day(0))
        #expect(r.volumeKg(e) == (76 + 10) * 8)
        #expect(r.externalVolumeKg(e) == 80)          // the belt alone
        #expect(r.bodyweightVolumeKg(e) == 76 * 8)    // the body alone
        #expect(r.externalVolumeKg(e) + r.bodyweightVolumeKg(e) == r.volumeKg(e))
    }

    @Test func barbellWorkIsEntirelyExternal() {
        let r = resolver([(day(-1), 80)])
        let e = entry("Barbell_Bench_Press_-_Medium_Grip", [(100, 5)], on: day(0))
        #expect(r.volumeKg(e) == 500)
        #expect(r.bodyweightVolumeKg(e) == 0)
    }

    @Test func stretchingContributesNothingEvenWithABodyweight() {
        let r = resolver([(day(-1), 80)])
        let e = entry("Calf_Stretch_Hands_Against_Wall", [(0, 30)], on: day(0))
        #expect(r.volumeKg(e) == 0)
    }

    // MARK: - Timed holds

    @Test func aPlanksSecondsBecomeRepEquivalents() {
        let r = resolver([(day(-1), 80)])
        // 60 s at 0.60 x 80 kg = 20 rep-equivalents x 48 kg.
        let e = entry("Plank", [(0, 60)], on: day(0))
        #expect(r.repEquivalents(exId: "Plank", set: RecordedSet(w: 0, r: 60)) == 20)
        #expect(r.volumeKg(e) == 960)
    }

    // MARK: - Estimated 1RM

    @Test func bodyweightLiftsFinallyHaveAnEstimated1RM() {
        let r = resolver([(day(-1), 80)])
        let e = entry("Pullups", [(0, 10)], on: day(0))
        // Was zero, because 0 kg x anything is zero — which is why pull-ups never
        // appeared in Strength or PRs at all.
        #expect(e.e1rm == 0)
        #expect(r.e1rm(e) == Formulas.e1rmRounded(kg: 76, reps: 10))
    }

    @Test func externalLiftsKeepTheirEstimated1RM() {
        let r = resolver([(day(-1), 80)])
        let e = entry("Barbell_Bench_Press_-_Medium_Grip", [(100, 5)], on: day(0))
        #expect(r.e1rm(e) == e.e1rm)
    }

    @Test func aHoldsE1rmUsesRepEquivalentsNotSeconds() {
        let r = resolver([(day(-1), 80)])
        let e = entry("Plank", [(0, 60)], on: day(0))
        // Epley over 60 "reps" would triple the load; 20 rep-equivalents is the honest read.
        #expect(r.e1rm(e) == Formulas.e1rmRounded(kg: 48, reps: 20))
    }
}
