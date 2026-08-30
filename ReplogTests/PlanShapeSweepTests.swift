//
//  PlanShapeSweepTests.swift
//  ReplogTests
//
//  The promise onboarding makes, checked against every answer a person can give.
//
//  A user chose 3 days a week and 85-minute sessions and was handed "Carry-On: Hotel Room
//  Maintenance" — a 20-minute program — as a plan containing a single Monday. Neither failure
//  was specific to that program or those answers: session length was collected and then never
//  looked at again, and the builder created one workout per day TEMPLATE rather than per
//  session in the week, so every program declaring more sessions than it has templates was
//  under-delivered.
//
//  Fixing the two reported symptoms would not have found the other 130 combinations that were
//  wrong for the same reasons. So this sweeps the whole answer space — every goal, experience,
//  frequency, session length and equipment set — and asserts the invariants that make a plan
//  a plan. It runs the real generation pipeline (deterministic path, no model) end to end.
//
//  These are properties, not examples: adding a program to the library, or a goal to the quiz,
//  extends the sweep automatically rather than needing a new test written for it.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct PlanShapeSweepTests {

    private static let kits: [(name: String, equipment: Set<Equipment>)] = [
        ("full gym", EquipmentAccess.fullGym.allowedEquipment.intersection(Set(Equipment.selectable))),
        ("home", [.dumbbell, .bands, .bodyOnly]),
        ("bodyweight only", [.bodyOnly]),
    ]

    /// Every combination the onboarding quiz can produce, at the resolutions that matter:
    /// the frequency chips (2...7) and the ends and middle of the session-length slider.
    private static func personas() -> [(tag: String, answers: QuizAnswers)] {
        var all: [(String, QuizAnswers)] = []
        for goal in Goal.allCases {
            for experience in Experience.allCases {
                for days in 2...7 {
                    for minutes in [20, 45, 90] {
                        for kit in kits {
                            var answers = QuizAnswers()
                            answers.goal = goal
                            answers.experience = experience
                            answers.daysPerWeek = days
                            answers.minutesPerSession = minutes
                            answers.equipmentTypes = kit.equipment
                            if goal == .sport { answers.sport = .running }
                            all.append(("\(goal)/\(experience)/\(days)d/\(minutes)min/\(kit.name)", answers))
                        }
                    }
                }
            }
        }
        return all
    }

    private func service() -> AIPlanService {
        AIPlanService(catalog: ExerciseCatalog(bundle: .main),
                      programCatalog: ProgramCatalog(bundle: .main),
                      forceFallback: true)
    }

    @Test func everyAnswerCombinationProducesAWeekTheAthleteAskedFor() async {
        let programs = ProgramCatalog(bundle: .main)
        let service = service()

        for persona in Self.personas() {
            let plan = await service.generate(persona.answers).plan

            // The number on the result screen is the number of workouts in the plan. This is
            // the failure that shipped: "3 days/week" over a plan with one Monday in it.
            #expect(plan.workouts.count == persona.answers.daysPerWeek,
                    "\(persona.tag): got \(plan.workouts.count) workouts")

            // A workout with nothing in it is not a session.
            #expect(plan.workouts.allSatisfy { !$0.items.isEmpty }, "\(persona.tag): empty workout")

            // Two workouts on one weekday means one of them is unreachable from Today.
            #expect(Set(plan.workouts.map(\.day)).count == plan.workouts.count,
                    "\(persona.tag): two workouts share a weekday")

            // A repeated template is a real thing (PPL twice a week); two workouts the
            // athlete cannot tell apart in a list is not.
            #expect(Set(plan.workouts.map(\.name)).count == plan.workouts.count,
                    "\(persona.tag): duplicate workout names")

            // A program is only used when it fits the time the athlete has; otherwise the
            // plan is generated to their own answers, and carries no programId.
            if let id = plan.programId, let program = programs.program(id: id) {
                let ratio = Double(program.sessionMinutes) / Double(persona.answers.minutesPerSession)
                #expect(ratio >= 0.5 && ratio <= 1.35,
                        "\(persona.tag): \(id) is \(program.sessionMinutes) min")
            }
        }
    }

    @Test func aDeclaredInjuryNeverCostsTheAthleteATrainingDay() async {
        // A knee injury removes every candidate from a leg day, and the builder used to skip
        // the session it could not fill: five days requested came back as three. The same
        // missing-days failure the day-template bug caused, reached by a different route.
        let service = service()
        var injurySets: [Set<Injury>] = Injury.allCases.map { [$0] }
        injurySets.append(Set(Injury.allCases))   // everything hurts
        injurySets.append([])

        for injuries in injurySets {
            for goal in Goal.allCases {
                for days in [3, 5] {
                    for kit in Self.kits where kit.name != "home" {
                        var answers = QuizAnswers()
                        answers.goal = goal
                        answers.daysPerWeek = days
                        answers.minutesPerSession = 60
                        answers.equipmentTypes = kit.equipment
                        answers.injuries = injuries
                        if goal == .sport { answers.sport = .running }

                        let label = injuries.isEmpty ? "none"
                            : injuries.map(\.rawValue).sorted().joined(separator: "+")
                        let plan = await service.generate(answers).plan

                        #expect(plan.workouts.count == days,
                                "[\(label)] \(goal)/\(days)d/\(kit.name): got \(plan.workouts.count)")
                        #expect(plan.workouts.allSatisfy { !$0.items.isEmpty },
                                "[\(label)] \(goal)/\(days)d/\(kit.name): empty workout")
                    }
                }
            }
        }
    }

    @Test func theReportedCaseIsFixed() async {
        // 3 days a week, 85-minute sessions, full gym. The bug report, as a test.
        var answers = QuizAnswers()
        answers.goal = .buildMuscle
        answers.daysPerWeek = 3
        answers.minutesPerSession = 85
        answers.equipmentTypes = [.barbell, .dumbbell, .machine, .cable, .bodyOnly]

        let result = await service().generate(answers)
        #expect(result.plan.workouts.count == 3)
        #expect(Set(result.plan.workouts.map(\.day)).count == 3)
        #expect(result.plan.programId != "travel_hotel_20min")

        if let id = result.plan.programId,
           let program = ProgramCatalog(bundle: .main).program(id: id) {
            #expect(program.sessionMinutes >= 43, "a 20-minute program for 85 minutes of training time")
        }
    }
}
