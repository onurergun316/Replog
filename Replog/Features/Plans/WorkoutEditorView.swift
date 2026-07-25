//
//  WorkoutEditorView.swift
//  Replog
//
//  Edit one training day: name, weekday (taken days disabled), exercises with
//  expandable set steppers, add/remove exercises, delete the workout. Exercise cards
//  are long-press draggable to reorder, so this is a `List` (the only container with
//  native reordering on iOS 26) styled as the app's cards via `plainListRow`.
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
    @State private var showRestSheet = false
    @State private var detailRef: ExerciseRef?
    /// Bumped on every committed drag, purely to drive the confirmation haptic.
    @State private var moves = 0

    private var defaultRest: Int { (settingsList.first ?? context.appSettings()).restSeconds }

    /// Weekdays used by the plan's other workouts (disabled in the picker).
    /// Extras don't hold a weekday, so they never lock one.
    private var takenDays: Set<Weekday> {
        Set((workout.plan?.workouts ?? []).filter { $0.id != workout.id && !$0.isExtra }.map(\.day))
    }

    var body: some View {
        List {
            Section {
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.plan?.name ?? "Plan").eyebrow()
                        TextField("Workout name", text: $workout.name)
                            .font(.screenTitle).foregroundStyle(Color.textPrimary)
                            .onChange(of: workout.name) { try? context.save() }
                    }

                    dayPicker

                    Text("\(workout.items.count) exercises · \(workout.setCount) sets · hold to reorder")
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                }
                .plainListRow(top: 8, bottom: 8)
            }

            Section {
                let items = workout.orderedItems
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                    .plainListRow(top: 8, bottom: 8)
                    .reorderAccessibilityActions(index: index, count: items.count, move: moveItems)
                }
                .onMove(perform: moveItems)
            }

            Section {
                Group {
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
                .plainListRow(top: 8, bottom: 8)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)          // the three sections only scope the drag, not the rhythm
        .reorderCommitFeedback(trigger: moves)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .hideKeyboardOnTap()
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { restForAllButton }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
            }
        }
        .sheet(isPresented: $showRestSheet) {
            SetRestSheet(title: "Rest for all exercises", initialSeconds: defaultRest) { applyRestToAll($0) }
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

    private var restForAllButton: some View {
        Button { showRestSheet = true } label: {
            Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.text2)
        }
    }

    private func applyRestToAll(_ seconds: Int?) {
        for item in workout.items { item.restSeconds = seconds }
        try? context.save()
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "Extra" first: a day-less slot the user can run any time. Never locked —
                // a plan can hold any number of extras.
                dayPill(label: "Extra", icon: "sparkles",
                        isSelected: workout.isExtra, disabled: false) { setExtra() }
                ForEach(Weekday.allCases) { day in
                    dayPill(label: day.short, icon: nil,
                            isSelected: !workout.isExtra && workout.day == day,
                            disabled: takenDays.contains(day)) { setDay(day) }
                }
            }
        }
    }

    private func dayPill(label: String, icon: String?, isSelected: Bool, disabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if disabled {
                    Image(systemName: "lock.fill").font(.system(size: 8, weight: .black))
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .black))
                }
                Text(label).font(.rounded(13, .heavy))
            }
            .foregroundStyle(isSelected ? .white : (disabled ? Color.text3 : Color.textPrimary))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
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
        // `.smooth` = a spring with ZERO bounce: a gentle glide with no overshoot/wobble.
        // `.snappy` (the app's usual curve) overshoots, which read as the "snappy/shaky" feel
        // on this large reveal. The row's own `.animation(.smooth, …)` matches this curve, so
        // the card and the rows it pushes below move as one.
        withAnimation(.smooth) { expandedItemID = expandedItemID == item.id ? nil : item.id }
    }

    /// Drag-to-reorder. Collapsing after a real move closes any set editor that just
    /// slid to a new position — a half-typed stepper left open over shuffled rows reads
    /// as the wrong exercise's sets. A drop back in place leaves the disclosure alone.
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard Reordering.apply(from: source, to: destination, in: workout.orderedItems) else { return }
        expandedItemID = nil
        try? context.save()
        moves += 1
    }

    private func setDay(_ day: Weekday) {
        guard !takenDays.contains(day) else { return }
        workout.day = day
        workout.isExtra = false
        try? context.save()
    }

    private func setExtra() {
        workout.isExtra = true
        try? context.save()
    }

    private func remove(_ item: PlanItem) {
        context.delete(item)
        try? context.save()
    }

    private func addSet(to item: PlanItem) {
        let last = item.orderedSets.last
        let set = SetTemplate(weightKg: last?.weightKg ?? 20, reps: last?.reps ?? 10,
                              rpe: last?.rpe ?? 8, order: Reordering.nextOrder(after: item.sets))
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

    /// Natural height of the revealed set editors, measured continuously *behind* the clip.
    /// The row always starts collapsed (the frame below is 0 high regardless of this value),
    /// so the first 0 → measured update is invisible; adding/removing a set re-measures and the
    /// height animates on the same curve. See `body` for why this keeps the `List` row smooth.
    @State private var revealHeight: CGFloat = 0

    private var effectiveRest: Int { item.restSeconds ?? defaultRest }

    var body: some View {
        VStack(spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

            // Measured-height clipped reveal. The old `if isExpanded { … }` handed the `List`
            // a *discrete* height jump: UIKit drew the new content at full size at once and
            // animated the cell frame on a separate timeline, so mid-transition the sets
            // overlapped the header (expand) or bled past the card onto the next row (collapse).
            // Instead the content is *always* in the tree at its natural height (`.fixedSize`,
            // so it can never be compressed), we measure that height, and reveal it through a
            // window we animate 0 ⇄ height — top-anchored so the header stays pinned, `.clipped()`
            // so nothing ever escapes the card. The row's reported height now changes
            // continuously on one `.smooth` curve, so the `List` self-sizes in lockstep.
            revealContent
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height },
                                  action: { revealHeight = $0 })
                .frame(height: isExpanded ? revealHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                // `.smooth` (spring, zero bounce) not `.snappy` (overshoots): a gentle glide,
                // no wobble at the end — the "smooth, not snappy" feel the reveal should have.
                .animation(.smooth, value: isExpanded)
                .animation(.smooth, value: revealHeight)
        }
        .padding(14)
        .cardSurface()
    }

    private var header: some View {
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
    }

    /// Everything revealed under the header, in one container so the reveal is a single
    /// view with a single measured height — never a pile of individually-transitioning rows.
    private var revealContent: some View {
        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity)
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
                // Editing clears `estimated`: the number is the athlete's now, not a
                // computed seed — which also stops a later session overwriting it.
                NumericStepperField(display: weightText, keyboard: .decimalPad,
                                    onMinus: { template.weightKg = max(0, template.weightKg - 2.5); template.markEdited(); onChange() },
                                    onPlus: { template.weightKg += 2.5; template.markEdited(); onChange() },
                                    onCommit: { if let kg = Formulas.parseWeightKg($0, units: .kg) { template.weightKg = kg; template.markEdited(); onChange() } })
            }
            VStack(spacing: 2) {
                Text("REPS").font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
                NumericStepperField(display: "\(template.reps)", keyboard: .numberPad,
                                    onMinus: { template.reps = max(1, template.reps - 1); template.markEdited(); onChange() },
                                    onPlus: { template.reps += 1; template.markEdited(); onChange() },
                                    onCommit: { if let reps = Formulas.parseReps($0) { template.reps = reps; template.markEdited(); onChange() } })
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
