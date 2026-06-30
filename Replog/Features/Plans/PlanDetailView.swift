//
//  PlanDetailView.swift
//  Replog
//
//  A plan's workouts: editable name, per-workout cards with Start, add a workout on
//  a free weekday, delete the plan.
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Bindable var plan: Plan

    var body: some View {
        List {
            Group {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan").eyebrow()
                    TextField("Plan name", text: $plan.name)
                        .font(.screenTitle).foregroundStyle(Color.textPrimary)
                        .onChange(of: plan.name) { try? context.save() }
                }
                Text("\(plan.workouts.count) workouts · \(plan.exerciseCount) exercises · swipe to delete")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                SectionHeader(title: "Workouts")
            }
            .plainListRow()

            ForEach(plan.orderedWorkouts) { workout in
                ZStack {
                    WorkoutCard(workout: workout, catalog: catalog) { start(workout) }
                    NavigationLink(value: workout) { EmptyView() }.opacity(0) // hides the List chevron
                }
                .plainListRow()
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteWorkout(workout) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Group {
                Button { addWorkout() } label: {
                    dashedButtonLabel(icon: "plus", title: "Add workout")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { deletePlan() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete plan")
                    }
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.down)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.down.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .plainListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteWorkout(_ workout: Workout) {
        context.delete(workout)
        try? context.save()
    }

    private func dashedButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(Color.accent.opacity(0.5))
        )
    }

    private func start(_ workout: Workout) {
        // One session at a time: resume an in-progress workout instead of starting a second.
        if let existing = (try? context.fetch(FetchDescriptor<ActiveSession>()))?.first {
            existing.isOpen = true
        } else {
            SessionBuilder.start(workout: workout, into: context)
        }
        try? context.save()
    }

    private func addWorkout() {
        PlanFactory.addWorkout(to: plan, into: context)
        try? context.save()
    }

    private func deletePlan() {
        context.delete(plan)
        try? context.save()
        dismiss()
    }
}

// MARK: - Workout card

struct WorkoutCard: View {
    let workout: Workout
    let catalog: ExerciseCatalog
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Pill(text: workout.day.short, style: .accentSoft)
                Text(workout.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: onStart) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 10, weight: .black))
                        Text("Start").font(.rounded(13, .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.accent))
                }
                .buttonStyle(.plain)
            }
            Text("\(workout.items.count) exercises · \(workout.setCount) sets")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            if !workout.orderedItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(workout.orderedItems.prefix(4)) { item in
                        ExerciseImageView(resourceName: catalog.exercise(id: item.exId)?.imageResourceNames.first,
                                          cornerRadius: 8)
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
