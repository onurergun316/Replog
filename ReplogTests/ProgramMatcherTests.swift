//
//  ProgramMatcherTests.swift
//  ReplogTests
//
//  Property + persona tests for the deterministic program matcher. These run against the
//  real bundled library so the gates/scoring are exercised on genuine data.
//

import Testing
import Foundation
@testable import Replog

struct ProgramMatcherTests {

    private let catalog = ProgramCatalog(bundle: .main)

    // Common equipment sets.
    private let fullGym: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyOnly,
                                           .bands, .kettlebells, .medicineBall]
    private let machineOnly: Set<Equipment> = [.machine]
    private let bodyweightOnly: Set<Equipment> = [.bodyOnly]

    // MARK: - Property gates

    @Test func machineOnlyUserNeverGetsABandsRequiredProgram() {
        let ctx = MatchContext(goal: .buildMuscle, equipment: machineOnly)
        let ranked = ProgramMatcher.rank(ctx, in: catalog)
        for match in ranked {
            #expect(!match.program.equipmentRequired.contains("bands"),
                    "\(match.program.id) requires bands but surfaced for a machine-only user")
        }
        // Sanity: the machine-only user still gets *some* programs (machine ones).
        #expect(!ranked.isEmpty)
    }

    @Test func bodyweightUserNeverGetsBarbellDumbbellCableMachineOrKettlebellPrograms() {
        let ctx = MatchContext(goal: .buildMuscle, equipment: bodyweightOnly)
        let ranked = ProgramMatcher.rank(ctx, in: catalog)
        let forbidden = ["barbell", "dumbbell", "cable", "machine", "kettlebell", "kettlebells"]
        for match in ranked {
            let req = Set(match.program.equipmentRequired.map { $0.lowercased() })
            #expect(req.isDisjoint(with: Set(forbidden)),
                    "\(match.program.id) requires gear a bodyweight user lacks")
        }
        #expect(!ranked.isEmpty)   // home_bodyweight / calisthenics / bands-free options remain
    }

    @Test func disclaimerProgramsAreNeverInTheAutoPickSet() {
        // Try several contexts; a disclaimer program must never be the auto-pick and must be
        // flagged non-auto-pickable wherever it survives the gates.
        let contexts = [
            MatchContext(goal: .buildMuscle, gender: .female, age: 33, equipment: fullGym),
            MatchContext(goal: .loseWeight, gender: .female, age: 52, equipment: fullGym),
            MatchContext(goal: .recomp, gender: .female, age: 45, equipment: fullGym),
        ]
        for ctx in contexts {
            let ranked = ProgramMatcher.rank(ctx, in: catalog)
            for match in ranked where match.program.requiresDisclaimerAcknowledgement {
                #expect(!match.autoPickable, "\(match.program.id) with disclaimer marked auto-pickable")
            }
            if let pick = ProgramMatcher.topAutoPick(ctx, in: catalog) {
                #expect(!pick.requiresDisclaimerAcknowledgement,
                        "auto-pick \(pick.id) carries a medical disclaimer")
            }
        }
    }

    @Test func prerequisiteProgramsAreGatedForNoHistoryUsersButAllowedWithHistory() throws {
        // run_10k_8wk requires "Can run 5K continuously".
        let prereqID = "run_10k_8wk"
        let noHistory = MatchContext(goal: .sport, sport: .running, age: 30,
                                     equipment: fullGym, satisfiesPrerequisites: false)
        let withHistory = MatchContext(goal: .sport, sport: .running, age: 30,
                                       equipment: fullGym, satisfiesPrerequisites: true)

        let gated = ProgramMatcher.rank(noHistory, in: catalog).map(\.id)
        #expect(!gated.contains(prereqID))

        let allowed = ProgramMatcher.rank(withHistory, in: catalog).map(\.id)
        #expect(allowed.contains(prereqID))
    }

    @Test func ageOutsideAudienceBandExcludesTheProgram() throws {
        // teen_foundations_3d targets a young band; a 50-year-old should be excluded from it.
        let teen = try #require(catalog.program(id: "teen_foundations_3d"))
        let older = MatchContext(goal: .buildMuscle, age: 50, equipment: fullGym)
        #expect(ProgramMatcher.score(teen, for: older) == nil || teen.audience.admits(age: 50))
        // Explicit: if the band excludes 50, the matcher drops it.
        if !teen.audience.admits(age: 50) {
            let ids = ProgramMatcher.rank(older, in: catalog).map(\.id)
            #expect(!ids.contains("teen_foundations_3d"))
        }
    }

    // MARK: - Sport ranking

    @Test func basketballSportUserGetsTheirSportProgramFirst() throws {
        let ctx = MatchContext(goal: .sport, sport: .basketball, age: 22, daysPerWeek: 3,
                               equipment: fullGym)
        let ranked = ProgramMatcher.rank(ctx, in: catalog)
        let top = try #require(ranked.first)
        #expect(top.program.sport?.lowercased() == "basketball",
                "expected basketball program first, got \(top.program.id)")
    }

    @Test func boxingSportUserGetsTheirSportProgramFirst() throws {
        let ctx = MatchContext(goal: .sport, sport: .boxing, age: 26, equipment: fullGym)
        let top = try #require(ProgramMatcher.rank(ctx, in: catalog).first)
        #expect(top.program.sport?.lowercased() == "boxing")
    }

    @Test func customSportWithNoMatchFallsBackToGeneralAthleteProgram() throws {
        // "underwater hockey" matches no program sport → GPP / general-athletic ranks first,
        // and no *other* sport-specific program leaks in.
        let ctx = MatchContext(goal: .sport, sport: .other, customSport: "underwater hockey",
                               age: 27, daysPerWeek: 3, equipment: fullGym)
        let ranked = ProgramMatcher.rank(ctx, in: catalog)
        let top = try #require(ranked.first)
        let generalAthletic = top.program.sport == nil
            || top.program.sport?.caseInsensitiveCompare("general") == .orderedSame
            || !Set(top.program.goals).isDisjoint(with: ["general_athleticism", "athletic_base"])
        #expect(generalAthletic, "expected a general-athletic fallback, got \(top.program.id)")
        // No mismatched specific-sport program should survive the sport gate.
        for m in ranked {
            let s = m.program.sport?.lowercased()
            #expect(s == nil || s == "general", "\(m.program.id) is sport \(s ?? "?") — should be gated")
        }
    }

    @Test func recognisedCustomSportMapsToItsProgram() throws {
        // "bouldering" → climbing. climb_support_2d requires bands; give the athlete bands.
        let ctx = MatchContext(goal: .sport, sport: .other, customSport: "bouldering",
                               age: 24, daysPerWeek: 2, equipment: fullGym)
        #expect(ctx.sportToken == "climbing")
        let ranked = ProgramMatcher.rank(ctx, in: catalog)
        let top = try #require(ranked.first)
        #expect(top.program.sport?.lowercased() == "climbing")
    }

    // MARK: - Soft scoring / personas

    @Test func femaleFocusedProgramRanksHigherForWomenButStaysAvailableToMen() throws {
        // glute_lower_emphasis_4d is female_focused and requires a machine.
        let program = try #require(catalog.program(id: "glute_lower_emphasis_4d"))
        let womanCtx = MatchContext(goal: .buildMuscle, gender: .female, age: 28, equipment: fullGym)
        let manCtx = MatchContext(goal: .buildMuscle, gender: .male, age: 28, equipment: fullGym)

        let womanScore = try #require(ProgramMatcher.score(program, for: womanCtx)).score
        let manMatch = try #require(ProgramMatcher.score(program, for: manCtx))
        #expect(womanScore > manMatch.score)   // higher for women
        #expect(manMatch.autoPickable)          // still available to men
    }

    @Test func beginnerGetsBeginnerProgramsScoredForExperience() throws {
        let ctx = MatchContext(goal: .buildMuscle, experience: .beginner, age: 25,
                               daysPerWeek: 3, equipment: fullGym)
        let beginnerProgram = try #require(catalog.program(id: "beginner_full_body_3d"))
        let match = try #require(ProgramMatcher.score(beginnerProgram, for: ctx))
        #expect(match.reasons.contains { $0.localizedCaseInsensitiveContains("beginner") })
    }

    @Test func daysPerWeekFitBoostsAnExactMatch() throws {
        let program = try #require(catalog.program(id: "beginner_full_body_3d")) // 3 days
        let fits = MatchContext(goal: .buildMuscle, daysPerWeek: 3, equipment: fullGym)
        let misses = MatchContext(goal: .buildMuscle, daysPerWeek: 6, equipment: fullGym)
        let fitScore = try #require(ProgramMatcher.score(program, for: fits)).score
        let missScore = try #require(ProgramMatcher.score(program, for: misses)).score
        #expect(fitScore > missScore)
    }

    @Test func fatLossPersonaTopPickTargetsFatLossOrConditioning() throws {
        let ctx = MatchContext(goal: .loseWeight, experience: .intermediate, age: 35,
                               daysPerWeek: 4, equipment: fullGym)
        let pick = try #require(ProgramMatcher.topAutoPick(ctx, in: catalog))
        let tokens = Set(pick.goals).union([pick.category])
        let fatLossy: Set<String> = ["weight_loss", "fat_loss", "conditioning", "work_capacity", "energy"]
        #expect(!tokens.isDisjoint(with: fatLossy), "fat-loss persona picked \(pick.id)")
    }

    @Test func everySurvivingProgramSatisfiesTheEquipmentGate() {
        // Cross-check the invariant across many personas.
        let personas: [MatchContext] = [
            MatchContext(goal: .buildMuscle, equipment: fullGym),
            MatchContext(goal: .loseWeight, equipment: machineOnly),
            MatchContext(goal: .recomp, equipment: [.dumbbell, .bodyOnly]),
            MatchContext(goal: .buildMuscle, equipment: bodyweightOnly),
            MatchContext(goal: .sport, sport: .running, equipment: [.bodyOnly], satisfiesPrerequisites: true),
        ]
        for ctx in personas {
            for match in ProgramMatcher.rank(ctx, in: catalog) {
                #expect(ProgramMatcher.equipmentSatisfied(match.program, by: ctx.equipment))
            }
        }
    }

    @Test func rankingIsDeterministicAndScoreSorted() {
        let ctx = MatchContext(goal: .buildMuscle, age: 30, daysPerWeek: 4, equipment: fullGym)
        let first = ProgramMatcher.rank(ctx, in: catalog)
        let second = ProgramMatcher.rank(ctx, in: catalog)
        #expect(first.map(\.id) == second.map(\.id))                 // deterministic
        #expect(first.map(\.score) == first.map(\.score).sorted(by: >)) // sorted desc
    }
}

// MARK: - Fitting the athlete's actual answers

@MainActor
struct ProgramFitTests {

    private let programs = ProgramCatalog(bundle: .main)

    private func athlete(days: Int, minutes: Int, goal: Goal = .buildMuscle) -> MatchContext {
        MatchContext(goal: goal, experience: .beginner, age: 28, daysPerWeek: days,
                     minutesPerSession: minutes,
                     equipment: [.barbell, .dumbbell, .machine, .cable, .bodyOnly, .bands])
    }

    // MARK: Session length

    @Test func aProgramThatFillsTheSessionScoresBest() {
        // 50 minutes of program for 55 minutes of time is the shape we want.
        #expect(ProgramMatcher.sessionFitScore(programMinutes: 50, athleteMinutes: 55) == 26)
    }

    @Test func aProgramThatNeedsMoreTimeThanTheAthleteHasIsAllButDisqualified() {
        // It cannot be finished, which is worse than any amount of goal alignment is worth.
        #expect(ProgramMatcher.sessionFitScore(programMinutes: 60, athleteMinutes: 20) == -60)
    }

    @Test func underUseIsPenalisedInProportion() {
        // The bug: a 20-minute program and a 40-minute one scored identically against 90
        // minutes, so the shorter could win on unrelated points. Closer must score higher.
        let twenty = ProgramMatcher.sessionFitScore(programMinutes: 20, athleteMinutes: 90)
        let forty = ProgramMatcher.sessionFitScore(programMinutes: 40, athleteMinutes: 90)
        let sixty = ProgramMatcher.sessionFitScore(programMinutes: 60, athleteMinutes: 90)
        #expect(twenty < forty)
        #expect(forty < sixty)
        #expect(twenty < 0)
    }

    @Test func sessionFitIsAboutProportionNotMinutes() {
        // Half the time you have is half the time you have, at any scale.
        #expect(ProgramMatcher.sessionFitScore(programMinutes: 10, athleteMinutes: 20)
                == ProgramMatcher.sessionFitScore(programMinutes: 45, athleteMinutes: 90))
    }

    @Test func anUnknownSessionLengthScoresNeutralRatherThanGuessing() {
        #expect(ProgramMatcher.sessionFitScore(programMinutes: 0, athleteMinutes: 60) == 0)
        #expect(ProgramMatcher.sessionFitScore(programMinutes: 45, athleteMinutes: 0) == 0)
    }

    @Test func theTwentyMinuteProgramLosesToAnAthleteWithAnHourAndAHalf() throws {
        // The reported bug, at the level of the decision that caused it.
        let hotel = try #require(programs.program(id: "travel_hotel_20min"))
        let ranked = ProgramMatcher.rank(athlete(days: 3, minutes: 85), in: programs)
        let hotelRank = try #require(ranked.firstIndex { $0.id == hotel.id })
        #expect(hotelRank > 0, "the 20-minute hotel program was still the top recommendation")
        #expect(!ProgramMatcher.fitsTheAthlete(hotel, for: athlete(days: 3, minutes: 85)))
    }

    @Test func theSameProgramIsTheRightAnswerForSomeoneWhoActuallyHasTwentyMinutes() throws {
        let hotel = try #require(programs.program(id: "travel_hotel_20min"))
        #expect(ProgramMatcher.fitsTheAthlete(hotel, for: athlete(days: 3, minutes: 20)))
    }

    // MARK: Frequency

    @Test func theAthletesFrequencyOutweighsAGoalKeyword() {
        // "Three days a week" is a promise about someone's life, not a training preference.
        #expect(ProgramMatcher.dayFitScore(gap: 0) > 12 * 2)
        #expect(ProgramMatcher.dayFitScore(gap: 0) > ProgramMatcher.dayFitScore(gap: 1))
        #expect(ProgramMatcher.dayFitScore(gap: 3) < 0)
    }

    // MARK: Gates

    @Test func aProgramWithNoDayTemplatesIsNeverRecommended() {
        // It cannot be built into a plan: it would silently become a generic split under a
        // program's name. Better to never offer it.
        let ranked = ProgramMatcher.rank(athlete(days: 3, minutes: 30, goal: .loseWeight), in: programs)
        #expect(!ranked.contains { $0.id == "couch_to_5k_9wk" })
    }

    @Test func aProgramWrittenForAnotherAthleteDropsDownTheListWithoutDisappearing() {
        let male = MatchContext(goal: .buildMuscle, gender: .male, daysPerWeek: 4,
                                minutesPerSession: 55,
                                equipment: [.barbell, .dumbbell, .machine, .cable, .bodyOnly])
        let ranked = ProgramMatcher.rank(male, in: programs)
        // Still reachable — it is a good program and nobody is barred from it...
        #expect(ranked.contains { $0.id == "womens_upper_strength_4d" })
        // ...but it is not what the app opens with for a male athlete.
        #expect(ranked.first?.id != "womens_upper_strength_4d")
    }

    @Test func maintenanceIsNotRecomposition() {
        // Holding what you have is the opposite of changing it; counting "maintenance" as a
        // recomp match is what let a maintenance circuit outrank real training programs.
        let recomp = athlete(days: 3, minutes: 60, goal: .recomp)
        let ranked = ProgramMatcher.rank(recomp, in: programs)
        #expect(ranked.first?.id != "travel_hotel_20min")
    }
}
