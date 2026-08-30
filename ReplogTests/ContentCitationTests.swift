//
//  ContentCitationTests.swift
//  ReplogTests
//
//  Replog's programming is grounded in exercise science, but the athlete is never handed a
//  reading list: no author, year, journal or trial name appears anywhere the app can render
//  it. The science shapes the copy; it is not name-dropped at the person trying to train.
//
//  This guards that rule at the only place it can be guarded honestly — the shipped content
//  itself. Strings are harvested by reflection rather than field-by-field, so a new String
//  added to any bundled model is covered the day it is added, not the day someone remembers
//  to update this file.
//
//  Deliberately NOT covered: `WeightComparison.source`, which exists purely so a future
//  maintainer can re-verify a figure. It is never decoded into copy and never rendered.
//

import Testing
import Foundation
@testable import Replog

@MainActor
struct ContentCitationTests {

    // MARK: - What "naming a paper" looks like

    /// Each pattern is a way a citation shows up in practice, kept separate so a failure
    /// says which convention leaked rather than just "regex matched".
    private static let conventions: [(name: String, pattern: String, caseSensitive: Bool)] = [
        ("author list (\"et al\")", #"\bet al\b"#, false),
        ("a journal name",          #"\bJournal\b|\bCochrane\b"#, false),
        ("a position stand",        #"\bposition stand(s)?\b"#, false),
        // "Schoenfeld 2017", "Schoenfeld, Grgic & Krieger 2019", "Finch, G. (1943)".
        ("an author-year citation", #"\p{Lu}[\p{L}'’\-]+(?:\s*(?:,|&|and)\s*(?:\p{Lu}\.\s*)?\p{Lu}[\p{L}'’\-]+)*[\s,]*\(?\b(?:18|19|20)\d{2}\b\)?"#, true),
        ("a bare parenthetical year", #"\(\s*(?:18|19|20)\d{2}\s*\)"#, true),
        ("a governing-body citation", #"\b(NSCA|ACSM|ACOG|WHO)\b"#, true),
    ]

    /// The offending convention, or nil when the text names nothing.
    private static func citation(in text: String) -> String? {
        for convention in conventions {
            let options: NSRegularExpression.Options = convention.caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: convention.pattern, options: options) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                return "\(convention.name): \"\(text[r])\""
            }
        }
        return nil
    }

    /// Every `String` reachable from `subject`, paired with the key path it sits on.
    /// Recurses through structs, arrays and optionals; scalars and enums fall out naturally.
    private static func strings(in subject: Any, at path: String = "",
                                skipping skipped: Set<String> = []) -> [(path: String, text: String)] {
        if let text = subject as? String { return [(path, text)] }
        return Mirror(reflecting: subject).children.flatMap { child -> [(path: String, text: String)] in
            let label = child.label ?? "[]"
            guard !skipped.contains(label) else { return [] }
            // Optionals reflect as a single "some" child; don't let that clutter the path.
            let next = label == "some" ? path : (path.isEmpty ? label : "\(path).\(label)")
            return strings(in: child.value, at: next, skipping: skipped)
        }
    }

    /// Fails with the field and the exact offending text, so a leak is a one-line fix.
    private static func expectNoCitations(in subject: Any, label: String, skipping: Set<String> = [],
                                          sourceLocation: SourceLocation = #_sourceLocation) {
        for field in strings(in: subject, skipping: skipping) {
            if let found = citation(in: field.text) {
                Issue.record("\(label).\(field.path) names \(found)", sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: - The detector itself

    @Test func theDetectorRecognisesHowCitationsActuallyAppear() {
        let named = [
            "Schoenfeld et al. 2017 (dose-response of weekly sets)",
            "Schoenfeld, Grgic & Krieger 2019 (frequency at matched volume)",
            "Finch, G. (1943) Journal of Mammalogy 24(2):224-228",
            "Sherrington et al. 2019 Cochrane (exercise and fall prevention)",
            "Fragala et al. 2019 (NSCA position stand, resistance training for older adults)",
            "walk-run progression literature (Buist et al. 2008, GRONORUN trial)",
            "Seiler 2010",
        ]
        for text in named {
            #expect(Self.citation(in: text) != nil, "should have been caught: \(text)")
        }
    }

    @Test func theDetectorLeavesOrdinaryCoachingCopyAlone() {
        let clean = [
            "Weekly hard sets and muscle growth rise together",
            "12-20 hard sets per muscle per week is the productive band for growth",
            "Training a muscle twice a week beats once for the same weekly volume",
            "a 2026 Formula 1 car must weigh at least 768 kilograms with the driver aboard",
            "Add 2.5 kg per session while every rep stays crisp",
            "Rest 90-120 seconds between sets, longer on the heavy compounds",
        ]
        for text in clean {
            #expect(Self.citation(in: text) == nil, "false positive on: \(text)")
        }
    }

    // MARK: - The shipped content

    @Test func noBundledProgramNamesAPaper() {
        let programs = ProgramCatalog(bundle: .main).all
        #expect(programs.count >= 60, "the library should have loaded")
        for program in programs {
            Self.expectNoCitations(in: program, label: "program[\(program.id)]")
        }
    }

    @Test func noWeightComparisonCopyNamesAPaper() {
        let catalog = ComparisonCatalog.shared
        #expect(!catalog.isEmpty, "the comparison library should have loaded")
        // `source` is provenance for maintainers, never decoded into anything rendered.
        for comparison in catalog.objects + catalog.animals + catalog.strength {
            Self.expectNoCitations(in: comparison, label: "comparison[\(comparison.id)]", skipping: ["source"])
        }
    }

    @Test func theCoachsGroundingAndPromptsNameNoPapers() {
        #expect(Self.citation(in: CoachingKnowledge.principles) == nil)
        #expect(Self.citation(in: AIPlanService.framingInstructions) == nil)
        #expect(Self.citation(in: AIPlanService.selectionInstructions) == nil)
    }

    // MARK: - The generated report — what the athlete actually reads after onboarding

    @Test func noGeneratedPlanReportNamesAPaper() {
        let catalog = ExerciseCatalog(bundle: .main)
        let programs = ProgramCatalog(bundle: .main).all
        var answers = QuizAnswers()
        answers.goal = .buildMuscle
        answers.equipmentTypes = [.barbell, .dumbbell, .machine, .cable, .bodyOnly, .bands, .kettlebells, .medicineBall]

        for program in programs {
            let plan = ProgramPlanBuilder.plan(from: program, answers: answers, catalog: catalog)
            let report = ProgramPlanBuilder.report(for: program, plan: plan, answers: answers)
            Self.expectNoCitations(in: report, label: "report[\(program.id)]")
            // The markdown is the artefact that is saved and re-read from Profile.
            if let found = Self.citation(in: ReportComposer.markdown(report: report, plan: plan)) {
                Issue.record("report[\(program.id)] markdown names \(found)")
            }
        }
    }
}
