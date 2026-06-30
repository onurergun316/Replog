//
//  DomainModelTests.swift
//  ReplogTests
//
//  Covers the smaller value-type logic: weekday mapping, enum display/labels,
//  quiz-derived sets, splits, and scheduling.
//

import Testing
import Foundation
@testable import Replog

struct DomainModelTests {

    // MARK: Weekday

    @Test func weekdayCalendarMapping() {
        #expect(Weekday.sun.calendarWeekday == 1)
        #expect(Weekday.sat.calendarWeekday == 7)
        #expect(Weekday.mon.tag == "MON")
        #expect(Weekday.wed.short == "Wed")
    }

    @Test func weekdayFromDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-06-30 is a Tuesday.
        let date = DateComponents(calendar: cal, year: 2026, month: 6, day: 30, hour: 12).date!
        #expect(Weekday.from(date, calendar: cal) == .tue)
    }

    // MARK: Enum display

    @Test func enumDisplayNames() {
        #expect(Muscle.lowerBack.displayName == "Lower Back")
        #expect(Equipment.bodyOnly.displayName == "Bodyweight")
        #expect(Equipment.ezCurlBar.displayName == "EZ Curl Bar")
        #expect(ExerciseCategory.olympicWeightlifting.displayName == "Olympic Weightlifting")
        #expect(Goal.recomp.displayName == "Build muscle & lose fat")
        #expect(Goal.buildMuscle.shortName == "Hypertrophy")
        #expect(Units.lb.label == "lb")
        #expect(Level.expert.displayName == "Expert")
    }

    // MARK: Quiz-derived mappings

    @Test func equipmentAccessAllowedSets() {
        #expect(EquipmentAccess.bodyweight.allowedEquipment == [.bodyOnly, .bands])
        #expect(EquipmentAccess.home.allowedEquipment.contains(.dumbbell))
        #expect(!EquipmentAccess.home.allowedEquipment.contains(.barbell))
        #expect(EquipmentAccess.fullGym.allowedEquipment.contains(.barbell))
    }

    @Test func injuryAvoidedMuscles() {
        var answers = QuizAnswers()
        answers.injuries = [.knee, .shoulder]
        #expect(answers.avoidedMuscles == [.quadriceps, .hamstrings, .calves, .shoulders])
        #expect(Injury.postInjuryRecovery.avoidMuscles.isEmpty)
    }

    @Test func sportPriorityMuscles() {
        #expect(Sport.running.priorityMuscles.first == .quadriceps)
        #expect(Sport.swimming.priorityMuscles.contains(.lats))
    }

    // MARK: Splits & scheduling

    @Test func splitChoiceByDays() {
        #expect(Split.choose(forDays: 2).dayTemplates.count == 2)
        #expect(Split.choose(forDays: 3).planName == "Push · Pull · Legs")
        #expect(Split.choose(forDays: 6).dayTemplates.count == 6)
    }

    @Test func generatorWeekdaySpread() {
        #expect(PlanGenerator.weekdays(count: 3) == [.mon, .wed, .fri])
        #expect(PlanGenerator.weekdays(count: 2) == [.mon, .thu])
        #expect(PlanGenerator.weekdays(count: 6).count == 6)
    }

    @Test func schedulingFindsFreeDays() {
        #expect(WeekdayPlanner.firstFreeDay(excluding: [.mon, .wed]) == .fri)
        #expect(WeekdayPlanner.firstFreeDay(excluding: Set(Weekday.allCases)) == nil)
        #expect(WeekdayPlanner.isAvailable(.tue, usedByOthers: [.mon]))
        #expect(!WeekdayPlanner.isAvailable(.mon, usedByOthers: [.mon]))
    }

    // MARK: Image resource naming

    @Test func exerciseImageNamesMatchPipeline() throws {
        let catalog = ExerciseCatalog(bundle: .main)
        let ex = try #require(catalog.exercise(id: "Barbell_Bench_Press_-_Medium_Grip"))
        #expect(ex.imageResourceNames.allSatisfy { !$0.contains("/") && !$0.contains(".jpg") })
    }
}
