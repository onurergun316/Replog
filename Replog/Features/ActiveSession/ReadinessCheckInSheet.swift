//
//  ReadinessCheckInSheet.swift
//  Replog
//
//  Optional, one-tap-per-question readiness check shown before a session starts. Never
//  blocking: "Skip" starts the session untouched; "Start" applies the readiness modulation
//  (see `ReadinessModulator`) and records the check-in for the coach. Completion is called
//  with the ratings, or nil when skipped.
//

import SwiftUI

struct ReadinessCheckInSheet: View {
    /// Called with the ratings on "Start", or nil on "Skip".
    let onComplete: (ReadinessCheckIn?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sleep: ReadinessRating = .good
    @State private var soreness: ReadinessRating = .good
    @State private var stress: ReadinessRating = .good

    private var checkIn: ReadinessCheckIn {
        ReadinessCheckIn(sleep: sleep, soreness: soreness, stress: stress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you feeling?").eyebrow()
                Text("Quick readiness check")
                    .font(.rounded(22, .black)).foregroundStyle(Color.textPrimary)
                Text("Optional — we'll tune today's session to match. Skip anytime.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            }

            ratingRow("Sleep", icon: "bed.double.fill", selection: $sleep,
                      labels: ["Good", "OK", "Poor"])
            ratingRow("Soreness", icon: "figure.strengthtraining.traditional", selection: $soreness,
                      labels: ["None", "Some", "High"])
            ratingRow("Stress", icon: "brain.head.profile", selection: $stress,
                      labels: ["Low", "OK", "High"])

            Spacer(minLength: 0)

            PrimaryButton(title: "Start workout") {
                onComplete(checkIn); dismiss()
            }
            Button("Skip") { onComplete(nil); dismiss() }
                .font(.rounded(15, .heavy)).foregroundStyle(Color.text2)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func ratingRow(_ title: String, icon: String,
                           selection: Binding<ReadinessRating>, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accent)
                Text(title).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
            }
            HStack(spacing: 8) {
                ForEach(Array(ReadinessRating.allCases.enumerated()), id: \.offset) { i, rating in
                    let selected = selection.wrappedValue == rating
                    Button {
                        withAnimation(.snappy) { selection.wrappedValue = rating }
                    } label: {
                        Text(labels[i])
                            .font(.rounded(14, .heavy))
                            .foregroundStyle(selected ? .white : Color.text2)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                .fill(selected ? Color.accent : Color.surface2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
