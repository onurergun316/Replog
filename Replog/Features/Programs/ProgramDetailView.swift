//
//  ProgramDetailView.swift
//  Replog
//
//  Reader-facing detail for a bundled library program: who it's for, the science behind it,
//  the principles it is built on, what to expect, and its cautions. A medical disclaimer, when
//  present, is shown as a prominent must-acknowledge banner. Reachable from the onboarding
//  result screen and from a plan's detail screen.
//

import SwiftUI

struct ProgramDetailView: View {
    let program: WorkoutProgram
    var showsDoneButton: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if program.requiresDisclaimerAcknowledgement, let disclaimer = program.medicalDisclaimer {
                    disclaimerBanner(disclaimer)
                }

                if !program.whoIsItFor.isEmpty {
                    section("Who it's for", body: program.whoIsItFor)
                }
                if !program.scienceRationale.isEmpty {
                    section("The science", body: program.scienceRationale)
                }
                if !program.principles.isEmpty {
                    principlesSection
                }
                if !program.expectedResults.isEmpty {
                    section("What to expect", body: program.expectedResults)
                }
                if !program.cautions.isEmpty {
                    section("Cautions", body: program.cautions)
                }
                if !program.whoShouldAvoid.isEmpty {
                    section("Who should avoid it", body: program.whoShouldAvoid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("About this program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(program.name)
                .font(.screenTitle).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                if program.daysPerWeek > 0 { Pill(text: "\(program.daysPerWeek) days/week", style: .soft) }
                if program.durationWeeks > 0 { Pill(text: "\(program.durationWeeks) weeks", style: .soft) }
                if program.sessionMinutes > 0 { Pill(text: "~\(program.sessionMinutes) min", style: .soft) }
                if let sport = program.sport, !sport.isEmpty {
                    Pill(text: sport.capitalized, style: .accentSoft)
                }
            }
        }
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
            Text(body)
                .font(.bodyText).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var principlesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it's built on").font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
            ForEach(Array(program.principles.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Color.accent).frame(width: 6, height: 6).padding(.top, 7)
                    Text(item).font(.rounded(14, .semibold)).foregroundStyle(Color.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func disclaimerBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.down)
                Text("Please read before starting").font(.rounded(15, .heavy)).foregroundStyle(Color.down)
            }
            Text(text)
                .font(.rounded(14, .semibold)).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Talk to a qualified clinician before beginning if any of this applies to you.")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.down.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.down.opacity(0.5), lineWidth: 1))
    }
}
