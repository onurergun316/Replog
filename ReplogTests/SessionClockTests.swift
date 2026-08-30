//
//  SessionClockTests.swift
//  ReplogTests
//
//  The measurement that `sessionMinutes` never was.
//
//  An athlete set aside 80 minutes, was given 5 exercises and 17 sets, and asked whether that
//  was really 80 minutes. It was about 50. Nothing in the app could answer the question,
//  because nothing measured a session — the matcher trusted a number typed into a JSON file
//  and the result screen echoed the athlete's own request back at them.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct SessionClockTests {

    private let programs = ProgramCatalog(bundle: .main)

    private func slot(_ pattern: MovementPattern, sets: Int, reps: String, rest: Int?) -> ProgramSlot {
        ProgramSlot(pattern: pattern, variant: nil, primaryMuscles: [], sets: sets,
                    reps: reps, intensity: "RPE 8", restSeconds: rest)
    }

    // MARK: - One set

    @Test func aCompoundRepCostsMoreThanAnIsolationRep() {
        let squat = slot(.squat, sets: 3, reps: "10", rest: 180)
        let curl = slot(.isolationArms, sets: 3, reps: "10", rest: 60)
        #expect(SessionClock.setSeconds(for: squat) == 35)    // 10 × 3.5s
        #expect(SessionClock.setSeconds(for: curl) == 25)     // 10 × 2.5s
    }

    @Test func aTimedSetIsItsOwnDuration() {
        #expect(SessionClock.setSeconds(for: slot(.coreBrace, sets: 3, reps: "45s", rest: 60)) == 45)
    }

    @Test func aPerSideSetIsBothSides() {
        let single = slot(.lunge, sets: 3, reps: "10", rest: 90)
        let perSide = slot(.lunge, sets: 3, reps: "10/side", rest: 90)
        #expect(SessionClock.setSeconds(for: perSide) == SessionClock.setSeconds(for: single) * 2)
    }

    @Test func aRangeStartsAtItsLowerBound() {
        // Same convention the plan itself is built on.
        #expect(SessionClock.setSeconds(for: slot(.squat, sets: 3, reps: "6-10", rest: 180))
                == SessionClock.setSeconds(for: slot(.squat, sets: 3, reps: "6", rest: 180)))
    }

    // MARK: - One day

    @Test func theFinalRestIsNotCounted() {
        // You leave after the last set rather than resting one more time.
        let day = ProgramDay(name: "D", slots: [slot(.squat, sets: 2, reps: "5", rest: 120)])
        let d = SessionClock.duration(for: day)
        #expect(d.restSeconds == 120)        // 2 sets × 120s, minus the trailing one
    }

    @Test func timeIsAttributedToWhereItActuallyGoes() {
        let day = ProgramDay(name: "Push", slots: [
            slot(.horizontalPush, sets: 4, reps: "8", rest: 180),
            slot(.isolationArms, sets: 3, reps: "12", rest: 60),
        ])
        let d = SessionClock.duration(for: day)

        let expectedWork: Double = (4 * 8 * 3.5) + (3 * 12 * 2.5)
        let expectedRest: Double = (4 * 180) + (3 * 60) - 60
        #expect(d.workSeconds == expectedWork)
        #expect(d.restSeconds == expectedRest)
        #expect(d.setupSeconds == 120)                       // two loaded stations
        #expect(d.warmUpSeconds == SessionClock.heavyWarmUpSeconds)
        #expect(d.totalSeconds == d.workSeconds + d.restSeconds + d.setupSeconds + d.warmUpSeconds)
    }

    @Test func aStretchingDayDoesNotGetALiftersRest() {
        // A flat 90-second default computed a mobility routine at about twice its real length.
        let day = ProgramDay(name: "Mobility", slots: [
            slot(.stretchStatic, sets: 3, reps: "30s", rest: nil),
            slot(.mobilityDrill, sets: 3, reps: "30s", rest: nil),
        ])
        let d = SessionClock.duration(for: day)
        let expectedRest: Double = (3 * 15) + (3 * 15) - 15
        #expect(d.restSeconds == expectedRest)
        #expect(d.warmUpSeconds == SessionClock.lightWarmUpSeconds)
        #expect(d.minutes < 8)
    }

    @Test func anEmptyDayCostsNothing() {
        let d = SessionClock.duration(for: ProgramDay(name: "", slots: []))
        #expect(d.totalSeconds == 0)
        #expect(d.minutes == 0)
    }

    // MARK: - The reported case

    @Test func theProgramTheAthleteGotIsNowhereNearEightyMinutes() throws {
        // 3 days, 80 minutes requested, 5 exercises and 17-18 sets delivered.
        let ppl = try #require(programs.program(id: "ppl_3d"))
        let mean = try #require(SessionClock.meanDuration(for: ppl))

        #expect(mean.minutes > 45)
        #expect(mean.minutes < 60)
        #expect(mean.minutes < Double(ppl.sessionMinutes))   // it does not even meet its own claim
        let longest = try #require(SessionClock.longestDayMinutes(for: ppl))
        #expect(longest < 70)
    }

    @Test func theLibrarysDeclaredMinutesAreNotAMeasurement() {
        // Systemic, not one program: the declared figure is hand-written and unvalidated.
        // This records the true gap rather than asserting the library is correct.
        var overstating = 0, measured = 0
        for program in programs.all where !program.days.isEmpty {
            guard let mean = SessionClock.meanDuration(for: program), program.sessionMinutes > 0 else { continue }
            measured += 1
            if mean.minutes < Double(program.sessionMinutes) * 0.8 { overstating += 1 }
        }
        // 19 of the measurable programmes prescribe under 80% of what they claim. This
        // records the gap rather than asserting the library is right; it should fall as the
        // declared figures are corrected, and this is the test that will notice.
        #expect(measured > 20)
        #expect(overstating >= 15, "\(overstating) of \(measured) measurable programmes overstate")
    }

    @Test func everyMeasurableDayMeasuresToSomethingPlausible() {
        // No measurable day should compute as a 2-minute session or a 3-hour one. A wild
        // figure means a slot was mis-read — which is how a 20-metre carry became ten
        // minutes. Days the schema cannot express are excluded by measurement, not fudged.
        for program in programs.all {
            for day in program.days where SessionClock.canMeasure(day) {
                let minutes = SessionClock.duration(for: day).minutes
                #expect(minutes > 5 && minutes < 150,
                        "\(program.id)/\(day.name) computes at \(Int(minutes)) min")
            }
        }
    }

    @Test func aWeekProgressionTableIsNotMeasuredAtAll() {
        // "wk1: 20 min -> +5 min every 2 wks -> wk11: 45 min" parses to a one-rep set and a
        // two-minute session. Refusing to measure it is the honest answer; the caller falls
        // back to the declared figure.
        let table = ProgramSlot(pattern: .run, variant: nil, primaryMuscles: [], sets: 1,
                                reps: "wk1: 20 min -> wk11: 45 min", intensity: "easy",
                                restSeconds: nil)
        #expect(!SessionClock.canMeasure(table))
        #expect(!SessionClock.canMeasure(ProgramSlot(pattern: .run, variant: nil, primaryMuscles: [],
                                                     sets: 1, reps: "per variant", intensity: "",
                                                     restSeconds: nil)))
        #expect(!SessionClock.canMeasure(ProgramSlot(pattern: .swim, variant: nil, primaryMuscles: [],
                                                     sets: 1, reps: "8x100m 20s rest", intensity: "",
                                                     restSeconds: nil)))
        // Ordinary strength prescriptions stay measurable.
        #expect(SessionClock.canMeasure(slot(.squat, sets: 4, reps: "6-10", rest: 180)))
        #expect(SessionClock.canMeasure(slot(.coreBrace, sets: 3, reps: "30-60s", rest: 60)))
    }

    @Test func anUnmeasurableProgramReportsNoDurationRatherThanAWrongOne() throws {
        let halfMarathon = try #require(programs.program(id: "half_marathon_12wk"))
        #expect(SessionClock.meanDuration(for: halfMarathon) == nil)
        #expect(SessionClock.longestDayMinutes(for: halfMarathon) == nil)

        // And the strength programmes, which the schema does express, are measurable.
        let ppl = try #require(programs.program(id: "ppl_3d"))
        #expect(SessionClock.meanDuration(for: ppl) != nil)
    }

    @Test func mostOfTheLibraryCanBeMeasured() {
        // Recorded so a future content change that breaks measurability is visible.
        let measurable = programs.all.filter { SessionClock.canMeasure($0) }.count
        let withDays = programs.all.filter { !$0.days.isEmpty }.count
        #expect(measurable >= withDays / 2, "only \(measurable) of \(withDays) programmes measurable")
    }
}
