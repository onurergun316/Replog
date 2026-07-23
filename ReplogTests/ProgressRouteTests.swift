//
//  ProgressRouteTests.swift
//  ReplogTests
//
//  Route identity is the part of navigation that is pure and testable (SwiftUI views
//  are verified on device, per ARCHITECTURE.md). It matters here because the Progress
//  stack is now path-driven: NavigationPath stores these values, and two taps that
//  should be one entry — or one that should be two — is exactly the class of bug the
//  routing rewrite fixed.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ProgressRouteTests {

    @Test func domainRoutesAreDistinct() {
        let routes: [ProgressRoute] = [.calendar, .strength, .volume, .balance, .consistency, .body]
        #expect(Set(routes).count == routes.count)
    }

    @Test func aMuscleRouteIsIdentifiedByItsMuscle() {
        #expect(ProgressRoute.muscle(.chest) == ProgressRoute.muscle(.chest))
        #expect(ProgressRoute.muscle(.chest) != ProgressRoute.muscle(.lats))
        // Distinct from every domain route, so pushing "chest" can never collide with a card.
        #expect(ProgressRoute.muscle(.chest) != ProgressRoute.balance)
    }

    @Test func weekAndDayRoutesAreIdentifiedByTheirDate() {
        let monday = Date(timeIntervalSince1970: 1_780_000_000)
        let tuesday = monday.addingTimeInterval(86_400)

        #expect(ProgressRoute.week(monday) == ProgressRoute.week(monday))
        #expect(ProgressRoute.week(monday) != ProgressRoute.week(tuesday))
        #expect(ProgressRoute.day(monday) == ProgressRoute.day(monday))
        // A week and a day sharing a date are different screens.
        #expect(ProgressRoute.week(monday) != ProgressRoute.day(monday))
    }

    @Test func repeatedTapsOnOneRowStayOneStackEntryPerTap() {
        // NavigationPath permits duplicates by design; what matters is that equal values
        // hash equally, so a set of routes collapses and the stack's own bookkeeping is
        // predictable rather than accidental.
        let taps = Array(repeating: ProgressRoute.muscle(.chest), count: 7)
        #expect(Set(taps).count == 1)
    }

    @Test func exerciseRefsAreIdentifiedByExerciseId() {
        #expect(ExerciseRef(id: "Pullups") == ExerciseRef(id: "Pullups"))
        #expect(ExerciseRef(id: "Pullups") != ExerciseRef(id: "Pushups"))
    }
}
