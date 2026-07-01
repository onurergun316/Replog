//
//  PlanGeneratorTests.swift
//  ReplogTests
//
//  Exercises the deterministic plan engine against the real bundled catalog.
//

import Testing
import Foundation
@testable import Replog

struct PlanGeneratorTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private var generator: PlanGenerator { PlanGenerator(catalog: catalog) }

    @Test func isDeterministic() {
        var answers = QuizAnswers()
        answers.daysPerWeek = 3
        let a = generator.generate(answers)
        let b = generator.generate(answers)
        #expect(a == b)
    }

    @Test func daysPerWeekDrivesWorkoutCount() {
        for days in 2...7 {
            var answers = QuizAnswers()
            answers.daysPerWeek = days
            let plan = generator.generate(answers)
            let expected = Split.choose(forDays: days).dayTemplates.count
            #expect(plan.workouts.count == expected)
            // Every workout has a distinct nonzero set of exercises.
            #expect(plan.workouts.allSatisfy { !$0.items.isEmpty })
        }
    }

    @Test func sevenDaysFillsEveryWeekdayWithNoRestDay() {
        var answers = QuizAnswers()
        answers.daysPerWeek = 7
        let plan = generator.generate(answers)
        #expect(plan.workouts.count == 7)
        let days = plan.workouts.map(\.day)
        #expect(Set(days).count == 7)                 // 7 distinct weekdays
        #expect(Set(days) == Set(Weekday.allCases))   // every day used, no rest day
    }

    @Test func threeDaysProducesPushPullLegs() {
        var answers = QuizAnswers()
        answers.daysPerWeek = 3
        let plan = generator.generate(answers)
        #expect(plan.name == "Push · Pull · Legs")
        #expect(plan.workouts.map(\.day) == [.mon, .wed, .fri])
        #expect(plan.workouts.map(\.name) == ["Push Day", "Pull Day", "Leg Day"])
    }

    @Test func bodyweightAccessNeverPicksLoadedEquipment() {
        var answers = QuizAnswers()
        answers.equipment = .bodyweight
        let plan = generator.generate(answers)
        let allowed = EquipmentAccess.bodyweight.allowedEquipment
        for workout in plan.workouts {
            for item in workout.items {
                let ex = catalog.exercise(id: item.exId)
                if let eq = ex?.equipment {
                    #expect(allowed.contains(eq), "Picked \(eq) under bodyweight access")
                }
            }
        }
    }

    @Test func kneeInjuryAvoidsLoadingKneeMuscles() {
        var answers = QuizAnswers()
        answers.injuries = [.knee]
        let plan = generator.generate(answers)
        let avoid: Set<Muscle> = [.quadriceps, .hamstrings, .calves]
        for workout in plan.workouts {
            for item in workout.items {
                let ex = catalog.exercise(id: item.exId)
                let primaries = Set(ex?.primaryMuscles ?? [])
                #expect(primaries.isDisjoint(with: avoid),
                        "Exercise \(item.exId) primarily loads an injured region")
            }
        }
    }

    @Test func experienceScalesSetCount() {
        var beginner = QuizAnswers(); beginner.experience = .beginner
        var advanced = QuizAnswers(); advanced.experience = .advanced

        let begSets = generator.generate(beginner).workouts.first?.items.first?.sets.count ?? 0
        let advSets = generator.generate(advanced).workouts.first?.items.first?.sets.count ?? 0
        #expect(begSets == 3)
        #expect(advSets == 4)
    }

    @Test func goalDrivesRepRange() {
        var hypertrophy = QuizAnswers(); hypertrophy.goal = .buildMuscle
        var fatLoss = QuizAnswers(); fatLoss.goal = .loseWeight
        let hReps = generator.generate(hypertrophy).workouts.first?.items.first?.sets.first?.reps
        let fReps = generator.generate(fatLoss).workouts.first?.items.first?.sets.first?.reps
        #expect(hReps == 10)
        #expect(fReps == 13)
    }

    @Test func sportGoalPrioritizesSportMuscles() {
        var answers = QuizAnswers()
        answers.goal = .sport
        answers.sport = .running
        answers.daysPerWeek = 3
        let plan = generator.generate(answers)

        // Across the whole plan, the running priority muscles should be represented.
        let workedPrimaries: Set<Muscle> = plan.workouts.reduce(into: []) { acc, w in
            for item in w.items {
                acc.formUnion(catalog.exercise(id: item.exId)?.primaryMuscles ?? [])
            }
        }
        let runningKey: Set<Muscle> = [.quadriceps, .hamstrings, .calves, .glutes]
        #expect(!workedPrimaries.isDisjoint(with: runningKey))
    }

    @Test func customOtherSportStillGeneratesFullPlan() {
        var answers = QuizAnswers()
        answers.goal = .sport
        answers.sport = .other            // no fixed muscle bias → general fallback
        answers.customSport = "Fencing"
        answers.daysPerWeek = 3
        let plan = generator.generate(answers)
        #expect(plan.workouts.count == 3)
        for workout in plan.workouts { #expect(!workout.items.isEmpty) }
    }

    @Test func noDuplicateExercisesWithinAWorkout() {
        var answers = QuizAnswers()
        answers.daysPerWeek = 4
        let plan = generator.generate(answers)
        for workout in plan.workouts {
            let ids = workout.items.map(\.exId)
            #expect(Set(ids).count == ids.count)
        }
    }
}
