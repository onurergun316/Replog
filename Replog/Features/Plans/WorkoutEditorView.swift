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
    @Query private var settingsList: [AppSettings]

    @State private var expandedItemID: UUID?
    @State private var showPicker = false
    @State private var detailRef: ExerciseRef?

    private var defaultRest: Int { (settingsList.first ?? context.appSettings()).restSeconds }

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
                        defaultRest: defaultRest,
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
        .scrollDismissesKeyboard(.immediately)
        .hideKeyboardOnTap()
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { restForAllMenu }
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

    /// Presets used by the "set rest for all" menus (seconds).
    static let restPresets = [30, 45, 60, 90, 120, 180]

    private var restForAllMenu: some View {
        Menu {
            Section("Rest for all exercises") {
                ForEach(Self.restPresets, id: \.self) { seconds in
                    Button(Self.restLabel(seconds)) { applyRestToAll(seconds) }
                }
                Button("Use app default") { applyRestToAll(nil) }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.text2)
        }
    }

    /// Formats a rest duration like "1:30" for menus/labels.
    static func restLabel(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)s"
    }

    private func applyRestToAll(_ seconds: Int?) {
        for item in workout.items { item.restSeconds = seconds }
        try? context.save()
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    let disabled = takenDays.contains(day)
                    let isSelected = workout.day == day
                    Button { setDay(day) } label: {
                        HStack(spacing: 4) {
                            if disabled {
                                Image(systemName: "lock.fill").font(.system(size: 8, weight: .black))
                            }
                            Text(day.short).font(.rounded(13, .heavy))
                        }
                        .foregroundStyle(isSelected ? .white : (disabled ? Color.text3 : Color.textPrimary))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.45 : 1)
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
    let defaultRest: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onInfo: () -> Void
    let onRemove: () -> Void
    let onAddSet: () -> Void
    let onRemoveSet: (SetTemplate) -> Void
    let onChange: () -> Void

    private var effectiveRest: Int { item.restSeconds ?? defaultRest }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ExerciseThumbnail(resourceName: exercise?.imageResourceNames.first, size: 52, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise?.name ?? item.exId).font(.rounded(15, .heavy))
                        .foregroundStyle(Color.textPrimary).lineLimit(2)
                    Text("\(item.sets.count) sets · \(exercise?.primaryMuscles.first?.displayName ?? "—")")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                }
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    iconButton("info.circle", action: onInfo)
                    iconButton("minus", tint: .down, action: onRemove)
                }
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
                Divider().padding(.vertical, 10)
                restEditor
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var restEditor: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("REST BETWEEN SETS").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                Text(item.restSeconds == nil ? "Using app default" : "Custom for this exercise")
                    .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
            }
            Spacer()
            NumericStepperField(display: "\(effectiveRest)", keyboard: .numberPad,
                                onMinus: { setRest(effectiveRest - 15) },
                                onPlus: { setRest(effectiveRest + 15) },
                                onCommit: { if let v = Int($0.filter(\.isNumber)) { setRest(v) } })
            Text("sec").font(.rounded(11, .bold)).foregroundStyle(Color.text3)
        }
    }

    private func setRest(_ seconds: Int) {
        item.restSeconds = max(5, seconds)
        onChange()
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
                NumericStepperField(display: weightText, keyboard: .decimalPad,
                                    onMinus: { template.weightKg = max(0, template.weightKg - 2.5); onChange() },
                                    onPlus: { template.weightKg += 2.5; onChange() },
                                    onCommit: { if let kg = Formulas.parseWeightKg($0, units: .kg) { template.weightKg = kg; onChange() } })
            }
            VStack(spacing: 2) {
                Text("REPS").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                NumericStepperField(display: "\(template.reps)", keyboard: .numberPad,
                                    onMinus: { template.reps = max(1, template.reps - 1); onChange() },
                                    onPlus: { template.reps += 1; onChange() },
                                    onCommit: { if let reps = Formulas.parseReps($0) { template.reps = reps; onChange() } })
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
