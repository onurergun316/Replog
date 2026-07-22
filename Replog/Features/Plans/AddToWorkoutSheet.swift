//
//  AddToWorkoutSheet.swift
//  Replog
//
//  Adds (or removes) an exercise across the user's workouts. Opened from the Library
//  (swipe) and the exercise detail ("Add to workout"). Multi-select: tap any number of
//  workouts across any plans. Dismissed by swipe-down.
//

import SwiftUI
import SwiftData

struct AddToWorkoutSheet: View {
    let exIds: [String]
    @Environment(\.exerciseCatalog) private var catalog
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]

    /// The single exercise when exactly one is being added (drives the thumbnail header).
    private var singleExercise: Exercise? {
        exIds.count == 1 ? catalog.exercise(id: exIds[0]) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    exerciseHeader
                    if plans.isEmpty {
                        emptyState
                    } else {
                        ForEach(plans) { plan in
                            planSection(plan)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Add to Workout")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var exerciseHeader: some View {
        HStack(spacing: 12) {
            if let ex = singleExercise {
                ExerciseThumbnail(resourceName: ex.imageResourceNames.first, size: 48, cornerRadius: 12)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentSoft)
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Color.accent))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(singleExercise?.name ?? "\(exIds.count) exercises")
                    .font(.cardTitle).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text("Tap a workout to add or remove")
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
            }
            Spacer(minLength: 8)
        }
    }

    private func planSection(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: plan.name)
            if plan.orderedWorkouts.isEmpty {
                Text("No workouts in this plan yet")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plan.orderedWorkouts.enumerated()), id: \.element.id) { index, workout in
                        workoutRow(workout)
                        if index < plan.orderedWorkouts.count - 1 { Divider().padding(.leading, 14) }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        let allIn = exIds.allSatisfy { WorkoutMembership.contains($0, in: workout) }
        return Button { toggle(workout) } label: {
            HStack(spacing: 12) {
                Pill(text: workout.slotLabel, style: .accentSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                    Text("\(workout.items.count) exercises")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                }
                Spacer(minLength: 8)
                Image(systemName: allIn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22)).foregroundStyle(allIn ? Color.up : Color.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: allIn)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash").font(.system(size: 28)).foregroundStyle(Color.text3)
            Text("No plans yet").font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text("Create a plan first, then you can add exercises to its workouts.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func toggle(_ workout: Workout) {
        let allIn = exIds.allSatisfy { WorkoutMembership.contains($0, in: workout) }
        if allIn {
            // Every selected exercise is already here → remove them all.
            exIds.forEach { PlanFactory.removeExercise($0, from: workout, into: context) }
        } else {
            // Add only the ones that aren't in this workout yet.
            for id in exIds where !WorkoutMembership.contains(id, in: workout) {
                PlanFactory.addExercise(id, to: workout, into: context)
            }
        }
        try? context.save()
    }
}
