//
//  OnboardingViewModel.swift
//  Replog
//
//  Drives the step-by-step quiz: which steps apply, validation, and running the
//  deterministic generator behind the "Building your plan" spinner.
//

import Foundation
import Observation

/// How the quiz was entered.
enum OnboardingMode: Equatable {
    case firstRun       // first launch; finishing flips onboardingDone -> main app
    case generatePlan   // from Plans; finishing inserts a plan and reports it
}

enum OnboardingStep: Hashable {
    case welcome, goal, sport, experience, gender, age, height, weight, days, time, injuries, equipment, equipmentTypes, name, generating, result
}

@MainActor
@Observable
final class OnboardingViewModel {
    var answers = QuizAnswers()
    var index = 0
    /// When true, the name step is omitted (the name is already known — e.g. generating
    /// a second plan from inside the app).
    var skipName = false
    var generated: GeneratedPlan?
    /// The saved coach report markdown produced alongside the plan.
    var reportMarkdown: String = ""
    /// Whether Apple Intelligence (vs the deterministic fallback) produced the plan.
    var usedAppleIntelligence = false

    private let service: AIPlanService

    init(service: AIPlanService = AIPlanService()) {
        self.service = service
    }

    /// The active step list, omitting Sport unless the goal requires it.
    var steps: [OnboardingStep] {
        var s: [OnboardingStep] = [.welcome, .goal]
        if answers.goal == .sport { s.append(.sport) }
        s.append(contentsOf: [.experience, .gender, .age, .height, .weight, .days, .time,
                              .injuries, .equipment, .equipmentTypes])
        // Name is asked last — but only when we don't already know it.
        if !skipName { s.append(.name) }
        s.append(contentsOf: [.generating, .result])
        return s
    }

    var current: OnboardingStep { steps[min(index, steps.count - 1)] }

    /// True when advancing from the current step starts plan generation (drives the
    /// "Build my plan" CTA on whichever step is last before the spinner).
    var nextIsGenerating: Bool {
        let next = index + 1
        return next < steps.count && steps[next] == .generating
    }

    /// Progress 0…1 across the quiz (welcome = first, result = full).
    var progress: Double {
        guard steps.count > 1 else { return 1 }
        return Double(index) / Double(steps.count - 1)
    }

    var canGoBack: Bool { index > 0 && current != .generating && current != .result }

    /// Whether the current step's selection allows advancing.
    var canProceed: Bool {
        switch current {
        case .name: return !answers.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .sport:
            guard let sport = answers.sport else { return false }
            // "Other" also requires a typed sport name.
            return sport != .other || !answers.customSport.trimmingCharacters(in: .whitespaces).isEmpty
        case .equipmentTypes: return !answers.equipmentTypes.isEmpty
        default: return true
        }
    }

    /// Whether the primary CTA should be shown (hidden during the auto-advancing spinner).
    var showsPrimaryCTA: Bool { current != .generating }

    func back() {
        guard canGoBack else { return }
        index -= 1
        // Re-skip the sport step if we backed past a non-sport goal.
        if current == .sport && answers.goal != .sport { index -= 1 }
    }

    func advance() {
        guard index < steps.count - 1 else { return }
        index += 1
    }

    /// Generates the plan + report (Apple Intelligence when available, else deterministic).
    /// `history` is the user's logged training (empty on first run); it is digested into an
    /// `AthleteContext` so the planner grounds its choices in real data.
    func generate(history: [HistoryEntry] = []) async {
        let athlete = AthleteContext.make(history: history, catalog: service.generator.catalog)
        let result = await service.generate(answers, athlete: athlete)
        generated = result.plan
        reportMarkdown = result.reportMarkdown
        usedAppleIntelligence = result.usedAppleIntelligence
    }
}
