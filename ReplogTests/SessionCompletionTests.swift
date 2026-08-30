//
//  SessionCompletionTests.swift
//  ReplogTests
//
//  The sequence that plays after Save & Finish. Finishing deletes the session and the
//  workout cover is bound to it, so nothing may be raised until that cover has gone —
//  and the badge, being the rarer thing, goes first.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct SessionCompletionTests {

    private func badge(_ id: String) -> Badge {
        Badge(id: id, name: id.capitalized, family: .foundations, tier: .bronze,
              shape: .circle, motif: .chevrons, palette: "bronze",
              criterion: .workouts(1), hint: "Finish a workout.", meaning: "You started.")
    }

    private func insight(_ title: String) -> CoachInsight {
        CoachInsight(kind: .sessionDebrief, priority: .normal, title: title, body: "Because.")
    }

    // MARK: - Nothing is raised while the workout is still on screen

    @Test func finishingQueuesRatherThanPresents() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [insight("Session complete")])

        #expect(completion.hasPending)
        #expect(completion.stage == .idle)
        #expect(completion.badges.isEmpty)
    }

    @Test func presentingRaisesTheBadgeFirst() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [insight("Session complete")])

        #expect(completion.presentPending())
        #expect(completion.stage == .badges)
        #expect(completion.badges.map(\.id) == ["first"])
        #expect(!completion.hasPending)
    }

    // MARK: - The order

    @Test func theBadgeHandsOverToTheDebrief() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [insight("Session complete")])
        completion.presentPending()

        completion.advance()
        #expect(completion.stage == .debrief)
        #expect(completion.insights.map(\.title) == ["Session complete"])

        completion.advance()
        #expect(completion.stage == .idle)
        #expect(completion.insights.isEmpty)
        #expect(!completion.isPresenting)
    }

    @Test func everyBadgeOfTheSessionIsCarriedInOneStage() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first"), badge("tenth")], insights: [])
        completion.presentPending()

        // The overlay walks its own array, so both badges belong to the one stage.
        #expect(completion.badges.count == 2)
        completion.advance()
        #expect(completion.stage == .idle)
    }

    @Test func noBadgeGoesStraightToTheDebrief() {
        let completion = SessionCompletion()
        completion.finished(badges: [], insights: [insight("Session complete")])

        completion.presentPending()
        #expect(completion.stage == .debrief)

        completion.advance()
        #expect(completion.stage == .idle)
    }

    @Test func aBadgeWithNoDebriefEndsAfterTheCelebration() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [])
        completion.presentPending()

        completion.advance()
        #expect(completion.stage == .idle)
        #expect(completion.badges.isEmpty)
    }

    // MARK: - Nothing earned

    @Test func anEmptyFinishQueuesNothingAndPresentsNothing() {
        let completion = SessionCompletion()
        completion.finished(badges: [], insights: [])

        #expect(!completion.hasPending)
        #expect(!completion.presentPending())
        #expect(completion.stage == .idle)
    }

    @Test func aSecondEmptyFinishClearsAnEarlierQueue() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [])
        completion.finished(badges: [], insights: [])

        #expect(!completion.hasPending)
        #expect(!completion.presentPending())
    }

    // MARK: - Guards

    @Test func advancingWhileIdleDoesNothing() {
        let completion = SessionCompletion()
        completion.advance()
        #expect(completion.stage == .idle)
    }

    @Test func presentingTwiceDoesNotRestartTheSequence() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [])
        completion.presentPending()
        completion.advance()

        #expect(!completion.presentPending())
        #expect(completion.stage == .idle)
    }

    @Test func resetEndsTheSequenceWhereverItIs() {
        let completion = SessionCompletion()
        completion.finished(badges: [badge("first")], insights: [insight("Session complete")])
        completion.presentPending()

        completion.reset()
        #expect(completion.stage == .idle)
        #expect(completion.badges.isEmpty)
        #expect(completion.insights.isEmpty)
        #expect(!completion.hasPending)
    }
}
