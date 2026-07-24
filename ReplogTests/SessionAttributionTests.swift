//
//  SessionAttributionTests.swift
//  ReplogTests
//
//  Recovering which workout a session came from, for history finished before that was
//  recorded. The rules that matter: a partial finish still matches, an exact match beats
//  a superset, and an unresolvable session stays unnamed rather than being guessed at.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct SessionAttributionTests {

    private func workout(_ name: String, _ exIds: [String],
                         plan: String = "PPL") -> SessionAttribution.Candidate {
        SessionAttribution.Candidate(id: UUID(), workoutName: name, planName: plan, exIds: exIds)
    }

    private let push = ["Bench", "Incline", "Fly", "Triceps"]
    private let pull = ["Row", "Pulldown", "Curl", "Facepull"]

    @Test func matchesTheWorkoutASessionWasBuiltFrom() {
        let candidates = [workout("Day 1", push), workout("Day 2", pull)]
        let match = SessionAttribution.match(sessionExIds: pull, candidates: candidates)
        #expect(match?.workoutName == "Day 2")
        #expect(match?.planName == "PPL")
    }

    @Test func matchesAPartialFinishToTheWorkoutItAbandoned() {
        // Two of four exercises logged: fully contained by Day 1, only half its union.
        // Ranking on overlap alone would leave every abandoned session unnamed.
        let candidates = [workout("Day 1", push), workout("Day 2", pull)]
        let match = SessionAttribution.match(sessionExIds: ["Bench", "Incline"],
                                             candidates: candidates)
        #expect(match?.workoutName == "Day 1")
    }

    @Test func prefersTheExactWorkoutOverOneThatMerelyContainsIt() {
        let candidates = [
            workout("Everything", push + pull),      // contains it, but is twice its size
            workout("Day 1", push),                  // exactly it
        ]
        let match = SessionAttribution.match(sessionExIds: push, candidates: candidates)
        #expect(match?.workoutName == "Day 1")
    }

    @Test func toleratesASwappedExercise() {
        let candidates = [workout("Day 1", push), workout("Day 2", pull)]
        // Three of the four still line up — enough to keep the name.
        let match = SessionAttribution.match(sessionExIds: ["Bench", "Incline", "Fly", "Dip"],
                                             candidates: candidates)
        #expect(match?.workoutName == "Day 1")
    }

    @Test func refusesToNameASessionThatMatchesNothing() {
        let candidates = [workout("Day 1", push), workout("Day 2", pull)]
        #expect(SessionAttribution.match(sessionExIds: ["Squat", "Leg Press", "Calf"],
                                         candidates: candidates) == nil)
    }

    @Test func refusesToBreakATieRatherThanGuessAName() {
        // Two workouts explain the session equally well; a coin flip would put the wrong
        // name on real history.
        let candidates = [workout("Day 1", push), workout("Day 4", push)]
        #expect(SessionAttribution.match(sessionExIds: push, candidates: candidates) == nil)
    }

    @Test func namesNothingWithoutEitherSideOfTheComparison() {
        #expect(SessionAttribution.match(sessionExIds: [], candidates: [workout("Day 1", push)]) == nil)
        #expect(SessionAttribution.match(sessionExIds: push, candidates: []) == nil)
    }

    @Test func containmentLeadsAndOverlapBreaksTheTie() {
        let exact = SessionAttribution.score(sessionExIds: Set(push), candidate: workout("A", push))
        let superset = SessionAttribution.score(sessionExIds: Set(push),
                                                candidate: workout("B", push + pull))
        #expect(exact.containment == 1 && superset.containment == 1)
        #expect(exact.overlap == 1)
        #expect(superset.overlap == 0.5)
        #expect(exact > superset)
    }
}
