//
//  PlannerEvalTests.swift
//  ReplogTests
//
//  Property-based evaluation of the planner across synthetic personas (see `PlannerEval`).
//
//  Fallback caveat: `FoundationModels` is unavailable in the iOS Simulator, so these runs
//  exercise the DETERMINISTIC `PlanGenerator` fallback, not the live Apple Intelligence
//  path. The properties are written to hold for BOTH engines (they constrain the plan, not
//  the wording), but the live model's picks must still be verified on device. The
//  history-signal properties assert the SIGNAL the planner consumes (`AthleteContext`) is
//  correct; making the deterministic engine act on that signal is the B-series progression
//  work (see BACKLOG), so the deterministic prescription is checked as a fixed contract here.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct PlannerEvalTests {

    private let catalog = ExerciseCatalog(bundle: .main)
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private var personas: [EvalPersona] { EvalPersonas.all(catalog: catalog, now: now) }

    /// The deterministic engine each persona's plan comes from in the simulator.
    private func plan(for persona: EvalPersona) -> GeneratedPlan {
        PlanGenerator(catalog: catalog).generate(persona.answers)
    }

    // MARK: - Structural completeness

    @Test func everyPersonaGetsANonEmptyPlan() {
        for persona in personas {
            let p = plan(for: persona)
            #expect(!p.workouts.isEmpty, "\(persona.name): plan has no workouts")
            #expect(p.workouts.allSatisfy { !$0.items.isEmpty },
                    "\(persona.name): a workout has no exercises")
        }
    }

    @Test func trainingDayCountMatchesRequest() {
        // For 3–6 requested days the split has exactly that many days.
        for persona in personas where (3...6).contains(persona.answers.daysPerWeek) {
            let p = plan(for: persona)
            #expect(p.workouts.count == persona.answers.daysPerWeek,
                    "\(persona.name): expected \(persona.answers.daysPerWeek) days, got \(p.workouts.count)")
        }
    }

    // MARK: - Equipment is never violated

    @Test func planNeverUsesUnavailableEquipment() {
        for persona in personas {
            let allowed = persona.answers.allowedEquipment
            let used = PlannerEvalMetrics.equipmentUsed(in: plan(for: persona), catalog: catalog)
            #expect(used.isSubset(of: allowed),
                    "\(persona.name): used \(used.subtracting(allowed)) outside allowed \(allowed)")
        }
    }

    @Test func machineOnlyUserNeverGetsBodyweightMovement() {
        let persona = try! #require(personas.first { $0.answers.equipmentTypes == [.machine] })
        let used = PlannerEvalMetrics.equipmentUsed(in: plan(for: persona), catalog: catalog)
        #expect(!used.contains(.bodyOnly), "machine-only plan surfaced a bodyweight movement")
        #expect(used == [.machine], "machine-only plan used non-machine equipment: \(used)")
    }

    @Test func bodyweightUserGetsOnlyBodyweightOrBands() {
        let persona = try! #require(personas.first { $0.answers.equipment == .bodyweight })
        let used = PlannerEvalMetrics.equipmentUsed(in: plan(for: persona), catalog: catalog)
        #expect(used.isSubset(of: [.bodyOnly, .bands]),
                "bodyweight plan used gym equipment: \(used)")
    }

    // MARK: - Injuries are respected

    @Test func injuredMusclesAreNotTrainedAsPrimaryMovers() {
        for persona in personas where !persona.answers.avoidedMuscles.isEmpty {
            let trained = PlannerEvalMetrics.primaryMusclesTrained(in: plan(for: persona), catalog: catalog)
            let violated = trained.intersection(persona.answers.avoidedMuscles)
            #expect(violated.isEmpty,
                    "\(persona.name): trained avoided muscles \(violated) as primary movers")
        }
    }

    // MARK: - Prescription matches goal & experience

    @Test func repsMatchTheGoal() {
        for persona in personas {
            let reps = PlannerEvalMetrics.prescribedReps(in: plan(for: persona))
            let expected = EvalPrescription.reps(for: persona.answers.goal)
            #expect(reps == [expected],
                    "\(persona.name): expected \(expected) reps, got \(reps.sorted())")
        }
    }

    @Test func rpeMatchesExperience() {
        for persona in personas {
            let rpe = PlannerEvalMetrics.prescribedRPE(in: plan(for: persona))
            let expected = EvalPrescription.rpe(for: persona.answers.experience)
            #expect(rpe == [expected],
                    "\(persona.name): expected RPE \(expected), got \(rpe.sorted())")
        }
    }

    // MARK: - Weekly volume lands in a defensible band

    @Test func weeklySetsPerTrainedMuscleAreInBand() {
        for persona in personas {
            let volume = PlannerEvalMetrics.weeklySetsPerMuscle(in: plan(for: persona), catalog: catalog)
            #expect(!volume.isEmpty, "\(persona.name): plan trained no muscles")
            for (muscle, sets) in volume {
                #expect(sets >= EvalPrescription.minEffectiveSets,
                        "\(persona.name): \(muscle.displayName) only \(sets) set(s)/week")
                #expect(sets <= EvalPrescription.maxRecoverableSets,
                        "\(persona.name): \(muscle.displayName) \(sets) set(s)/week is excessive")
            }
        }
    }

    @Test func planTrainsABalancedSetOfMuscles() {
        // A week's programming should touch several major regions, not one or two.
        for persona in personas {
            let trained = PlannerEvalMetrics.primaryMusclesTrained(in: plan(for: persona), catalog: catalog)
            #expect(trained.count >= 4,
                    "\(persona.name): only trained \(trained.count) muscle(s): \(trained.map(\.displayName).sorted())")
        }
    }

    // MARK: - History signal the planner consumes (ties to A1; live action is B-series)

    @Test func progressingHistorySurfacesAnUpwardTrend() {
        let persona = try! #require(personas.first { $0.name.contains("progressing") })
        let context = AthleteContext.make(history: persona.history, catalog: catalog, now: now)
        #expect(!context.isEmpty)
        // Every lift in a purely-progressing trail must read as trending up.
        for lift in context.lifts {
            let trend = try! #require(lift.trendPercent, "\(lift.name): no trend computed")
            #expect(trend > 0, "\(lift.name): expected upward trend, got \(trend)%")
        }
    }

    @Test func stallingHistorySurfacesAFlatTrend() {
        let persona = try! #require(personas.first { $0.name.contains("stalling") })
        let context = AthleteContext.make(history: persona.history, catalog: catalog, now: now)
        #expect(!context.isEmpty)
        for lift in context.lifts {
            #expect(lift.trendPercent == 0,
                    "\(lift.name): expected flat trend for a stalled lift, got \(String(describing: lift.trendPercent))")
        }
    }

    @Test func richHistoryProducesADifferentInBudgetPromptThanEmpty() {
        let persona = try! #require(personas.first { !$0.history.isEmpty })
        let context = AthleteContext.make(history: persona.history, catalog: catalog, now: now)
        let programs = ProgramCatalog(bundle: .main)
        let candidates = Array(ProgramMatcher.rank(MatchContext.from(persona.answers), in: programs)
            .filter { $0.autoPickable }.prefix(AIPlanService.maxCandidates))
        let rich = AIPlanService.framingPrompt(candidates: candidates, answers: persona.answers, athlete: context)
        let empty = AIPlanService.framingPrompt(candidates: candidates, answers: persona.answers)

        #expect(rich != empty, "\(persona.name): history did not change the prompt")
        #expect(rich.contains("RECENT LOGGED TRAINING"))

        // Even the richest persona's prompt must leave the full response reserve in-window.
        let inputTokens = PromptBudget.tokenCount(for: AIPlanService.framingInstructions)
            + PromptBudget.tokenCount(for: rich)
        #expect(inputTokens + PromptBudget.responseReserve <= PromptBudget.contextWindow,
                "\(persona.name): prompt overran the token budget")
    }

    // MARK: - Candidate list the model picks from also respects equipment

    @Test func candidateListNeverOffersUnavailableEquipment() {
        let generator = PlanGenerator(catalog: catalog)
        for persona in personas {
            let allowed = persona.answers.allowedEquipment
            // Sample the muscles a plan for this persona actually targets.
            let muscles = Array(PlannerEvalMetrics.primaryMusclesTrained(
                in: plan(for: persona), catalog: catalog))
            let candidates = generator.candidates(forMuscles: muscles, answers: persona.answers, limit: 14)
            for ex in candidates {
                #expect(allowed.contains(ex.equipment ?? .bodyOnly),
                        "\(persona.name): candidate \(ex.name) needs unavailable \(ex.equipment?.displayName ?? "bodyweight")")
            }
        }
    }
}
