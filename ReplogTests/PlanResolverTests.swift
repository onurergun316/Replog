//
//  PlanResolverTests.swift
//  ReplogTests
//
//  The AI per-day resolver: the model's numbered picks must map onto REAL catalog exercises,
//  carry their reasons, drop invalid/duplicate picks, and fill any shortfall.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct PlanResolverTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private func generator() -> PlanGenerator { PlanGenerator(catalog: catalog) }

    @Test func resolvesModelPicksToCatalogExercisesWithReasons() {
        let candidates = generator().candidates(forMuscles: [.chest, .shoulders, .triceps],
                                                answers: QuizAnswers(), limit: 14)
        #expect(candidates.count >= 5)
        let day = DayFraming(name: "Push", targetMuscles: ["chest", "shoulders", "triceps"],
                             exerciseCount: 4, reps: 10, rpe: 8, sets: 4)
        let selection = DaySelection(dayRationale: "Compound first.", picks: [
            ExercisePick(number: 1, reason: "Main chest press."),
            ExercisePick(number: 2, reason: "Shoulder work."),
            ExercisePick(number: 3, reason: "Triceps."),
            ExercisePick(number: 5, reason: "More volume."),
        ])
        let (items, notes) = PlanResolver().resolveDay(day: day, selection: selection, candidates: candidates)

        #expect(items.count == 4)
        #expect(items[0].exId == candidates[0].id)
        #expect(items[3].exId == candidates[4].id)
        #expect(items.allSatisfy { catalog.exercise(id: $0.exId) != nil })
        #expect(items.allSatisfy { $0.sets.count == 4 && $0.sets.allSatisfy { $0.reps == 10 && $0.rpe == 8 } })
        #expect(notes.count == 4)
        #expect(notes[0].reason == "Main chest press.")
    }

    @Test func invalidAndDuplicatePicksDroppedAndGapsFilled() {
        let candidates = generator().candidates(forMuscles: [.chest], answers: QuizAnswers(), limit: 14)
        let day = DayFraming(name: "X", targetMuscles: ["chest"], exerciseCount: 3, reps: 10, rpe: 8, sets: 3)
        let selection = DaySelection(dayRationale: "", picks: [
            ExercisePick(number: 999, reason: "out of range"),
            ExercisePick(number: 1, reason: "valid"),
            ExercisePick(number: 1, reason: "duplicate"),
        ])
        let (items, notes) = PlanResolver().resolveDay(day: day, selection: selection, candidates: candidates)

        #expect(items.count == 3)                       // gap-filled up to the requested count
        #expect(Set(items.map(\.exId)).count == 3)      // all unique
        #expect(notes.first?.reason == "valid")
        #expect(items.allSatisfy { catalog.exercise(id: $0.exId) != nil })
    }

    @Test func emptyReasonFallsBackToDefault() {
        let candidates = generator().candidates(forMuscles: [.chest], answers: QuizAnswers(), limit: 14)
        let day = DayFraming(name: "X", targetMuscles: ["chest"], exerciseCount: 3, reps: 10, rpe: 8, sets: 3)
        let selection = DaySelection(dayRationale: "", picks: [ExercisePick(number: 1, reason: "  ")])
        let (_, notes) = PlanResolver().resolveDay(day: day, selection: selection, candidates: candidates)
        #expect(notes.first?.reason == PlanResolver.defaultReason)
    }

    @Test func emptyCandidatesYieldsEmpty() {
        let day = DayFraming(name: "X", targetMuscles: [], exerciseCount: 3, reps: 10, rpe: 8, sets: 3)
        let (items, notes) = PlanResolver().resolveDay(
            day: day, selection: DaySelection(dayRationale: "", picks: []), candidates: [])
        #expect(items.isEmpty)
        #expect(notes.isEmpty)
    }

    @Test func candidatesRespectBodyweightEquipment() {
        var answers = QuizAnswers(); answers.equipment = .bodyweight
        let cands = generator().candidates(forMuscles: [.chest, .abdominals], answers: answers, limit: 14)
        #expect(!cands.isEmpty)
        let allowed = EquipmentAccess.bodyweight.allowedEquipment
        for ex in cands { if let eq = ex.equipment { #expect(allowed.contains(eq)) } }
    }

    @Test func candidatesAvoidInjuredRegions() {
        var answers = QuizAnswers(); answers.injuries = [.knee]
        let cands = generator().candidates(forMuscles: [.quadriceps, .hamstrings], answers: answers, limit: 14)
        let avoid: Set<Muscle> = [.quadriceps, .hamstrings, .calves]
        for ex in cands { #expect(Set(ex.primaryMuscles).isDisjoint(with: avoid)) }
    }
}
