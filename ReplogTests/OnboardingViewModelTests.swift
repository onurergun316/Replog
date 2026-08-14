//
//  OnboardingViewModelTests.swift
//  ReplogTests
//
//  Step navigation logic: conditional sport step, progress, back-skipping, gating.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct OnboardingViewModelTests {

    @Test func sportStepOnlyAppearsForSportGoal() {
        let vm = OnboardingViewModel()
        vm.answers.goal = .buildMuscle
        #expect(!vm.steps.contains(.sport))

        vm.answers.goal = .sport
        #expect(vm.steps.contains(.sport))
    }

    @Test func skipNameOmitsNameAndBuildsAfterEquipment() {
        let vm = OnboardingViewModel()
        vm.skipName = true
        #expect(!vm.steps.contains(.name))          // name step gone
        // The last input step before generating is now equipmentTypes.
        #expect(vm.steps.dropLast(2).last == .equipmentTypes)
        while vm.current != .equipmentTypes { vm.advance() }
        #expect(vm.nextIsGenerating)                // drives the "Build my plan" CTA
    }

    @Test func advanceAndBackWalkTheSteps() {
        let vm = OnboardingViewModel()
        #expect(vm.current == .welcome)
        vm.advance()
        #expect(vm.current == .goal)
        vm.advance()
        #expect(vm.current == .experience)
        vm.back()
        #expect(vm.current == .goal)
        vm.back()
        #expect(vm.current == .welcome)
        // Can't go back past the first step.
        vm.back()
        #expect(vm.index == 0)
    }

    @Test func nameStepIsAskedLastAndGatesProceed() {
        let vm = OnboardingViewModel()
        // Name is the final question before generating.
        #expect(vm.steps.dropLast(2).last == .name)
        while vm.current != .name { vm.advance() }
        #expect(!vm.canProceed)            // no name yet
        vm.answers.firstName = "  "        // whitespace doesn't count
        #expect(!vm.canProceed)
        vm.answers.firstName = "Jordan"
        #expect(vm.canProceed)
    }

    @Test func equipmentTypesStepGatesUntilSomethingSelected() {
        let vm = OnboardingViewModel()
        #expect(vm.steps.contains(.equipmentTypes))
        while vm.current != .equipmentTypes { vm.advance() }
        vm.answers.equipmentTypes = []
        #expect(!vm.canProceed)
        vm.answers.equipmentTypes = [.dumbbell]
        #expect(vm.canProceed)
    }

    @Test func quizCollectsHeightAndWeightSteps() {
        let vm = OnboardingViewModel()
        #expect(vm.steps.contains(.height))
        #expect(vm.steps.contains(.weight))
    }

    @Test func generateProducesPlanAndReportViaFallback() async {
        let vm = OnboardingViewModel(service: AIPlanService(catalog: ExerciseCatalog(bundle: .main),
                                                            forceFallback: true))
        vm.answers.daysPerWeek = 3
        await vm.generate()
        // The fallback is PROGRAM-DRIVEN: it materialises the top-ranked curated program
        // exactly as authored. Days per week is only a soft ranking signal in
        // `ProgramMatcher` (+20 - 7·gap, never a gate), and a program's `days` are session
        // TEMPLATES rotated across the week — nine of the 62 library programs deliberately
        // have `days.count != daysPerWeek`. So the workout count is the program's, not the
        // request's, and asserting 3 here asserted a contract this path never promised.
        // Exact day-count matching belongs to the legacy split engine and is asserted
        // against `PlanGenerator` in `PlannerEvalTests.trainingDayCountMatchesRequest`.
        #expect(vm.generated?.workouts.isEmpty == false)
        #expect(!vm.reportMarkdown.isEmpty)
        #expect(vm.usedAppleIntelligence == false)
    }

    @Test func progressIsMonotonicFromZeroToOne() {
        let vm = OnboardingViewModel()
        #expect(vm.progress == 0)
        var last = vm.progress
        while vm.index < vm.steps.count - 1 {
            vm.advance()
            #expect(vm.progress >= last)
            last = vm.progress
        }
        #expect(vm.progress == 1)
    }

    @Test func sportGoalRequiresASelectionToProceed() {
        let vm = OnboardingViewModel()
        vm.answers.goal = .sport
        // Walk to the sport step.
        while vm.current != .sport { vm.advance() }
        #expect(!vm.canProceed)          // no sport chosen yet
        vm.answers.sport = .running
        #expect(vm.canProceed)
    }

    @Test func otherSportRequiresTypedNameToProceed() {
        let vm = OnboardingViewModel()
        vm.answers.goal = .sport
        while vm.current != .sport { vm.advance() }
        vm.answers.sport = .other
        #expect(!vm.canProceed)          // "Other" with no text can't proceed
        vm.answers.customSport = "  "
        #expect(!vm.canProceed)          // whitespace doesn't count
        vm.answers.customSport = "Fencing"
        #expect(vm.canProceed)
    }

    @Test func backFromExperienceSkipsSportWhenGoalIsNotSport() {
        let vm = OnboardingViewModel()
        vm.answers.goal = .buildMuscle
        // welcome -> goal -> experience
        vm.advance(); vm.advance()
        #expect(vm.current == .experience)
        vm.back()
        #expect(vm.current == .goal)     // no sport step to land on
    }

    @Test func generatingHidesPrimaryCTA() {
        let vm = OnboardingViewModel()
        while vm.current != .generating { vm.advance() }
        #expect(!vm.showsPrimaryCTA)
        #expect(!vm.canGoBack)
    }

}
