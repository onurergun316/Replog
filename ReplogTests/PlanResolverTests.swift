//
//  PlanResolverTests.swift
//  ReplogTests
//
//  The AI hybrid resolver: an AI blueprint must map onto REAL catalog exercises with
//  valid ids, honoring equipment/injury constraints and the blueprint's rep scheme.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct PlanResolverTests {

    private let catalog = ExerciseCatalog(bundle: .main)

    private func resolver() -> PlanResolver {
        PlanResolver(generator: PlanGenerator(catalog: catalog))
    }

    private func sampleBlueprint() -> PlanBlueprint {
        PlanBlueprint(
            planName: "Push · Pull · Legs",
            headline: "Your Hypertrophy Plan",
            workouts: [
                WorkoutBlueprint(name: "Push Day", targetMuscles: ["chest", "shoulders", "triceps"],
                                 exerciseCount: 4, reps: 10, rpe: 8, sets: 4, rationale: "Press synergists together."),
                WorkoutBlueprint(name: "Pull Day", targetMuscles: ["lats", "biceps"],
                                 exerciseCount: 3, reps: 12, rpe: 7, sets: 3, rationale: "Pull synergists together."),
                WorkoutBlueprint(name: "Leg Day", targetMuscles: ["quadriceps", "hamstrings", "glutes"],
                                 exerciseCount: 5, reps: 8, rpe: 9, sets: 4, rationale: "Lower body."),
            ],
            philosophy: "p", whyThisSplit: "w", scienceNotes: "s", safetyNotes: "sf", encouragement: "e"
        )
    }

    @Test func resolvesToValidCatalogExercises() {
        let plan = resolver().resolve(sampleBlueprint(), answers: QuizAnswers())
        #expect(plan.workouts.count == 3)
        for workout in plan.workouts {
            #expect(!workout.items.isEmpty)
            for item in workout.items {
                // Every resolved exercise must be a real catalog entry (so images/refs exist).
                #expect(catalog.exercise(id: item.exId) != nil)
            }
        }
    }

    @Test func appliesBlueprintRepScheme() {
        let plan = resolver().resolve(sampleBlueprint(), answers: QuizAnswers())
        let push = plan.workouts.first { $0.name == "Push Day" }!
        let item = push.items.first!
        #expect(item.sets.count == 4)           // sets from blueprint
        #expect(item.sets.allSatisfy { $0.reps == 10 })
        #expect(item.sets.allSatisfy { $0.rpe == 8 })
    }

    @Test func weekdaysAreDistinctAcrossWorkouts() {
        let plan = resolver().resolve(sampleBlueprint(), answers: QuizAnswers())
        let days = plan.workouts.map(\.day)
        #expect(Set(days).count == days.count)
    }

    @Test func unrecognizedMusclesFallBackToPriorityAndStillResolve() {
        var bp = sampleBlueprint()
        bp.workouts = [WorkoutBlueprint(name: "Mystery", targetMuscles: ["xyz", "qwerty"],
                                        exerciseCount: 4, reps: 10, rpe: 8, sets: 3, rationale: "?")]
        let plan = resolver().resolve(bp, answers: QuizAnswers())
        #expect(plan.workouts.count == 1)
        #expect(!plan.workouts[0].items.isEmpty) // resolver recovered using priority muscles
    }

    @Test func bodyweightEquipmentStillProducesAPlan() {
        var answers = QuizAnswers()
        answers.equipment = .bodyweight
        let plan = resolver().resolve(sampleBlueprint(), answers: answers)
        for workout in plan.workouts {
            #expect(!workout.items.isEmpty)
            for item in workout.items { #expect(catalog.exercise(id: item.exId) != nil) }
        }
    }

    @Test func clampsOutOfRangeExerciseCount() {
        var bp = sampleBlueprint()
        bp.workouts = [WorkoutBlueprint(name: "Push", targetMuscles: ["chest"],
                                        exerciseCount: 99, reps: 10, rpe: 8, sets: 3, rationale: "x")]
        let plan = resolver().resolve(bp, answers: QuizAnswers())
        #expect(plan.workouts[0].items.count <= 6)
    }
}
