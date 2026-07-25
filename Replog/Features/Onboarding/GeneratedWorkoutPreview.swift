//
//  GeneratedWorkoutPreview.swift
//  Replog
//
//  A read-only preview of one generated workout, opened from the onboarding result
//  screen (before the plan is persisted). Lists the day's exercises with their sets
//  and target muscle, resolved from the catalog by exId.
//

import SwiftUI

/// Identifiable wrapper so a value-type `GeneratedWorkout` can drive `.sheet(item:)`.
struct GeneratedWorkoutRef: Identifiable {
    let id = UUID()
    let workout: GeneratedWorkout
}

struct GeneratedWorkoutPreview: View {
    let workout: GeneratedWorkout
    let catalog: ExerciseCatalog
    @Environment(\.dismiss) private var dismiss

    private var totalSets: Int { workout.items.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Pill(text: workout.day.tag, style: .accentSoft)
                        Text("\(workout.items.count) exercises · \(totalSets) sets")
                            .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(workout.items.enumerated()), id: \.offset) { _, item in
                        let ex = catalog.exercise(id: item.exId)
                        NavigationLink(value: ExerciseRef(id: item.exId)) {
                            HStack(spacing: 14) {
                                ExerciseThumbnail(exercise: ex, size: 52, cornerRadius: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ex?.name ?? item.exId)
                                        .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(2)
                                    Text("\(item.sets.count) sets · \(ex?.primaryMuscles.first?.displayName ?? "—")")
                                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.text3)
                            }
                            .padding(12)
                            .cardSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exId: ref.id, showProgress: false)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
