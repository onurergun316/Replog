//
//  ProgramPlanBuilderTests.swift
//  ReplogTests
//
//  Verifies the shared program → plan spine: deterministic slot resolution, model-pick
//  validation, slot skipping, the program-grounded report, and end-to-end persistence of the
//  program metadata + per-exercise rest through PlanFactory.
//

import Testing
import Foundation
import SwiftData
@testable import Replog

@MainActor
struct ProgramPlanBuilderTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private let programs = ProgramCatalog(bundle: .main)

    private func fullGymAnswers() -> QuizAnswers {
        var a = QuizAnswers()
        a.goal = .buildMuscle
        a.equipmentTypes = [.barbell, .dumbbell, .machine, .cable, .bodyOnly, .bands, .kettlebells, .medicineBall]
        return a
    }

    // MARK: - Deterministic plan

    @Test func deterministicPlanCarriesProgramIdRestAndParsedReps() throws {
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let plan = ProgramPlanBuilder.plan(from: program, answers: fullGymAnswers(), catalog: catalog)

        #expect(plan.programId == "beginner_full_body_3d")
        #expect(plan.progression?.type == program.progression.type)
        #expect(!plan.workouts.isEmpty)
        #expect(plan.workouts.allSatisfy { !$0.items.isEmpty })

        // Day A slot 1 is a squat, 3×5, rest 180s → first item mirrors that scheme.
        let firstItem = try #require(plan.workouts.first?.items.first)
        #expect(firstItem.restSeconds == 180)
        #expect(firstItem.sets.count == 3)
        #expect(firstItem.sets.allSatisfy { $0.reps == 5 })
        // The resolved exercise is a real leg compound.
        let ex = try #require(catalog.exercise(id: firstItem.exId))
        #expect(ex.primaryMuscles.contains { [.quadriceps, .glutes, .hamstrings].contains($0) })
    }

    @Test func timeBasedSlotEncodesSecondsInReps() throws {
        // Day A slot 4 is a core brace, "30-60s" → a timed 30s target.
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let plan = ProgramPlanBuilder.plan(from: program, answers: fullGymAnswers(), catalog: catalog)
        let core = try #require(plan.workouts.first?.items.last)
        #expect(core.sets.first?.reps == 30)
        #expect(core.restSeconds == 60)
    }

    // MARK: - Slot resolution rules

    @Test func slotWithNoCandidatesIsSkipped() {
        // A swim slot has no catalog match; a squat slot resolves — the day yields one item.
        let day = ProgramDay(name: "Mixed", slots: [
            ProgramSlot(pattern: .swim, sets: 1, reps: "200m", intensity: ""),
            ProgramSlot(pattern: .squat, sets: 3, reps: "5", intensity: "RPE 8", restSeconds: 120),
        ])
        let resolved = ProgramPlanBuilder.resolveDay(day, answers: fullGymAnswers(), catalog: catalog)
        #expect(resolved.items.count == 1)
        #expect(resolved.items.first?.restSeconds == 120)
    }

    @Test func validModelPickIsUsedInvalidFallsBackToTopCandidate() throws {
        let squat = ProgramSlot(pattern: .squat, sets: 3, reps: "5", intensity: "RPE 8")
        let day = ProgramDay(name: "Legs", slots: [squat])
        let answers = fullGymAnswers()
        let cands = ProgramPlanBuilder.candidates(for: squat, answers: answers, catalog: catalog)
        #expect(cands.count >= 2)

        // A valid pick (second candidate) is honoured over the deterministic top pick.
        let validPick = cands[1]
        let usedValid = ProgramPlanBuilder.resolveDay(day, answers: answers, catalog: catalog, picks: [validPick])
        #expect(usedValid.items.first?.exId == validPick.id)

        // An invalid pick (an isolation-arms movement) is rejected → top squat candidate used.
        let armPick = try #require(PatternMapping.candidates(for: .isolationArms,
            allowedEquipment: answers.allowedEquipment, in: catalog).first)
        let usedFallback = ProgramPlanBuilder.resolveDay(day, answers: answers, catalog: catalog, picks: [armPick])
        #expect(usedFallback.items.first?.exId == cands[0].id)
    }

    @Test func resolveDayDoesNotRepeatAnExerciseAcrossSlots() {
        // Two identical push slots must resolve to two different exercises.
        let push = ProgramSlot(pattern: .horizontalPush, sets: 3, reps: "8-12", intensity: "RPE 8")
        let day = ProgramDay(name: "Push", slots: [push, push])
        let resolved = ProgramPlanBuilder.resolveDay(day, answers: fullGymAnswers(), catalog: catalog)
        #expect(resolved.items.count == 2)
        #expect(resolved.items[0].exId != resolved.items[1].exId)
    }

    // MARK: - Report

    @Test func reportSurfacesProgramScienceAndCautions() throws {
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let answers = fullGymAnswers()
        let plan = ProgramPlanBuilder.plan(from: program, answers: answers, catalog: catalog)
        let report = ProgramPlanBuilder.report(for: program, plan: plan, answers: answers)
        #expect(report.whyThisSplit == program.scienceRationale)
        #expect(report.perDay.count == plan.workouts.count)
        #expect(report.perDay.allSatisfy { !$0.exercises.isEmpty })
    }

    @Test func reportFoldsInjuriesIntoSafetyNotes() throws {
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        var answers = fullGymAnswers()
        answers.injuries = [.knee]
        let plan = ProgramPlanBuilder.plan(from: program, answers: answers, catalog: catalog)
        let report = ProgramPlanBuilder.report(for: program, plan: plan, answers: answers)
        #expect(report.safetyNotes.contains("Knee"))
    }

    // MARK: - End-to-end persistence

    @Test func insertingAProgramPlanPersistsMetadataAndRest() throws {
        let program = try #require(programs.program(id: "beginner_full_body_3d"))
        let answers = fullGymAnswers()
        let gen = ProgramPlanBuilder.plan(from: program, answers: answers, catalog: catalog)

        let context = ModelContext(ReplogSchema.inMemoryContainer())
        let plan = PlanFactory.insert(gen, into: context, order: 0, reportMarkdown: "report")
        try context.save()

        #expect(plan.programId == "beginner_full_body_3d")
        #expect(plan.progressionType == program.progression.type)
        #expect(plan.progressionDeload == (program.progression.deload ?? ""))
        // Per-exercise rest survived into the stored PlanItem.
        let firstItem = try #require(plan.orderedWorkouts.first?.orderedItems.first)
        #expect(firstItem.restSeconds == 180)

        // Re-fetch to confirm it's actually persisted, not just in-memory on the object.
        let fetched = try context.fetch(FetchDescriptor<Plan>())
        #expect(fetched.first?.programId == "beginner_full_body_3d")
    }
}

// MARK: - The week a program actually prescribes

@MainActor
struct ProgramWeekTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private let programs = ProgramCatalog(bundle: .main)

    private func answers(days: Int) -> QuizAnswers {
        var a = QuizAnswers()
        a.goal = .buildMuscle
        a.daysPerWeek = days
        a.equipmentTypes = [.barbell, .dumbbell, .machine, .cable, .bodyOnly, .bands, .kettlebells, .medicineBall]
        return a
    }

    @Test func aOneTemplateProgramStillFillsTheWeek() throws {
        // The reported bug: 3 days a week arrived as a plan with a single Monday, because
        // this program describes its week with one repeated template.
        let hotel = try #require(programs.program(id: "travel_hotel_20min"))
        #expect(hotel.days.count == 1)
        #expect(hotel.daysPerWeek == 3)

        let week = ProgramPlanBuilder.weeklySchedule(for: hotel)
        #expect(week.count == 3)
        #expect(week.allSatisfy { $0.templateIndex == 0 })
    }

    @Test func repeatedSessionsAreNumberedSoTheyCanBeToldApart() throws {
        let hotel = try #require(programs.program(id: "travel_hotel_20min"))
        let names = ProgramPlanBuilder.weeklySchedule(for: hotel).map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.first == names.first?.replacingOccurrences(of: " (1)", with: ""))
    }

    @Test func aRotationRunsInOrderAndRepeats() throws {
        // Six days from three templates is that rotation twice, not three days.
        let ppl = try #require(programs.program(id: "ppl_6d"))
        let week = ProgramPlanBuilder.weeklySchedule(for: ppl)
        #expect(week.count == 6)
        #expect(week.map(\.templateIndex) == [0, 1, 2, 0, 1, 2])
        #expect(week[3].occurrence == 2)
    }

    @Test func theWeekFollowsTheAthleteWhenTheyAsk() throws {
        // The library holds only two 6-day programs and three 2-day ones, so binding the
        // plan to the program's own frequency shortchanges anyone at the edges.
        let beginner = try #require(programs.program(id: "beginner_full_body_3d"))
        #expect(ProgramPlanBuilder.weeklySchedule(for: beginner, sessions: 5).count == 5)
        #expect(ProgramPlanBuilder.weeklySchedule(for: beginner, sessions: 2).count == 2)
    }

    @Test func aWeekIsNeverLongerThanAWeek() throws {
        let beginner = try #require(programs.program(id: "beginner_full_body_3d"))
        #expect(ProgramPlanBuilder.weeklySchedule(for: beginner, sessions: 12).count == 7)
        #expect(ProgramPlanBuilder.weeklySchedule(for: beginner, sessions: 0).count == 1)
    }

    @Test func aProgramWithNoTemplatesHasNoWeek() throws {
        let running = try #require(programs.program(id: "couch_to_5k_9wk"))
        #expect(ProgramPlanBuilder.weeklySchedule(for: running).isEmpty)
    }

    @Test func aRepeatedTemplateResolvesToTheSameSessionEveryTime() throws {
        // Two Push days in a PPL week must not quietly contain different exercises.
        let ppl = try #require(programs.program(id: "ppl_6d"))
        let plan = ProgramPlanBuilder.plan(from: ppl, answers: answers(days: 6), catalog: catalog)
        #expect(plan.workouts.count == 6)
        #expect(plan.workouts[0].items.map(\.exId) == plan.workouts[3].items.map(\.exId))
    }

    @Test func everyBundledProgramFillsTheWeekItClaims() {
        // A library-wide guarantee rather than a per-program one: any program added later
        // that declares more sessions than it has templates is covered the day it lands.
        for program in programs.all where !program.days.isEmpty {
            let week = ProgramPlanBuilder.weeklySchedule(for: program)
            #expect(week.count == min(max(program.daysPerWeek, program.days.count), 7),
                    "\(program.id) built \(week.count) sessions for \(program.daysPerWeek) days/week")
            #expect(Set(week.map(\.name)).count == week.count, "\(program.id) has duplicate session names")
        }
    }
}
