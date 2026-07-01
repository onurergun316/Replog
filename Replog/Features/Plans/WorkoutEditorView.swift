//
//  WorkoutEditorView.swift
//  Replog
//
//  Edit one training day: name, weekday (taken days disabled), exercises with
//  expandable set steppers, add/remove exercises, delete the workout.
//

import SwiftUI
import SwiftData

struct WorkoutEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Bindable var workout: Workout

    @State private var expandedItemID: UUID?
    @State private var showPicker = false
    @State private var detailRef: ExerciseRef?

    /// Weekdays used by the plan's other workouts (disabled in the picker).
    private var takenDays: Set<Weekday> {
        Set((workout.plan?.workouts ?? []).filter { $0.id != workout.id }.map(\.day))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.plan?.name ?? "Plan").eyebrow()
                    TextField("Workout name", text: $workout.name)
                        .font(.screenTitle).foregroundStyle(Color.textPrimary)
                        .onChange(of: workout.name) { try? context.save() }
                }

                dayPicker

                Text("\(workout.items.count) exercises · \(workout.setCount) sets")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)

                ForEach(workout.orderedItems) { item in
                    ExerciseEditRow(
                        item: item,
                        exercise: catalog.exercise(id: item.exId),
                        isExpanded: expandedItemID == item.id,
                        onToggle: { toggle(item) },
                        onInfo: { detailRef = ExerciseRef(id: item.exId) },
                        onRemove: { remove(item) },
                        onAddSet: { addSet(to: item) },
                        onRemoveSet: { removeSet($0, from: item) },
                        onChange: { try? context.save() }
                    )
                }

                Button { showPicker = true } label: {
                    dashedLabel(icon: "plus", title: "Add exercise", color: .accent)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { deleteWorkout() } label: {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text("Delete workout") }
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.down)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.down.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
            }
        }
        .sheet(isPresented: $showPicker) {
            AddExercisePicker(existingIDs: Set(workout.items.map(\.exId))) { exId in
                PlanFactory.addExercise(exId, to: workout, into: context)
                try? context.save()
            }
        }
        .sheet(item: $detailRef) { ref in
            NavigationStack { ExerciseDetailView(exId: ref.id, showProgress: false) }
        }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    let disabled = takenDays.contains(day)
                    Button { setDay(day) } label: {
                        Text(day.short)
                            .font(.rounded(13, .heavy))
                            .foregroundStyle(workout.day == day ? .white : (disabled ? Color.text3 : Color.text2))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(workout.day == day ? Color.accent : Color.surface2))
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1)
                }
            }
        }
    }

    private func dashedLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) { Image(systemName: icon); Text(title) }
            .font(.rounded(15, .heavy)).foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(color.opacity(0.5)))
    }

    // MARK: Actions

    private func toggle(_ item: PlanItem) {
        withAnimation(.snappy) { expandedItemID = expandedItemID == item.id ? nil : item.id }
    }

    private func setDay(_ day: Weekday) {
        guard !takenDays.contains(day) else { return }
        workout.day = day
        try? context.save()
    }

    private func remove(_ item: PlanItem) {
        context.delete(item)
        try? context.save()
    }

    private func addSet(to item: PlanItem) {
        let last = item.orderedSets.last
        let set = SetTemplate(weightKg: last?.weightKg ?? 20, reps: last?.reps ?? 10,
                              rpe: last?.rpe ?? 8, order: item.sets.count)
        set.item = item
        context.insert(set)
        try? context.save()
    }

    private func removeSet(_ set: SetTemplate, from item: PlanItem) {
        context.delete(set)
        try? context.save()
    }

    private func deleteWorkout() {
        context.delete(workout)
        try? context.save()
        dismiss()
    }
}

// MARK: - Exercise edit row

private struct ExerciseEditRow: View {
    let item: PlanItem
    let exercise: Exercise?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInfo: () -> Void
    let onRemove: () -> Void
    let onAddSet: () -> Void
    let onRemoveSet: (SetTemplate) -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ExerciseImageView(resourceName: exercise?.imageResourceNames.first, cornerRadius: 12)
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.border, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise?.name ?? item.exId).font(.rounded(15, .heavy))
                        .foregroundStyle(Color.textPrimary).lineLimit(1)
                    Text("\(item.sets.count) Sets · \(exercise?.primaryMuscles.first?.displayName ?? "—")")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                }
                Spacer(minLength: 8)
                iconButton("info.circle", action: onInfo)
                iconButton("minus", tint: .down, action: onRemove)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            if isExpanded {
                Divider().padding(.vertical, 10)
                ForEach(Array(item.orderedSets.enumerated()), id: \.element.id) { index, set in
                    SetEditorRow(index: index + 1, template: set,
                                 canRemove: item.sets.count > 1,
                                 onRemove: { onRemoveSet(set) }, onChange: onChange)
                }
                Button(action: onAddSet) {
                    HStack(spacing: 5) { Image(systemName: "plus"); Text("Add set") }
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private func iconButton(_ symbol: String, tint: Color = .text2, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.surface2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single set editor (weight & reps steppers)

private struct SetEditorRow: View {
    let index: Int
    @Bindable var template: SetTemplate
    let canRemove: Bool
    let onRemove: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)").font(.rounded(13, .heavy)).foregroundStyle(Color.text3).frame(width: 16)

            VStack(spacing: 2) {
                Text("WEIGHT (kg)").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                StepperControl(value: weightText,
                               onMinus: { template.weightKg = max(0, template.weightKg - 2.5); onChange() },
                               onPlus: { template.weightKg += 2.5; onChange() })
            }
            VStack(spacing: 2) {
                Text("REPS").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                StepperControl(value: "\(template.reps)",
                               onMinus: { template.reps = max(1, template.reps - 1); onChange() },
                               onPlus: { template.reps += 1; onChange() })
            }
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.down.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var weightText: String {
        template.weightKg == template.weightKg.rounded() ? String(Int(template.weightKg)) : String(format: "%.1f", template.weightKg)
    }
}
