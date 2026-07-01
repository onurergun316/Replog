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
        #expect(vm.generated?.workouts.count == 3)
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
