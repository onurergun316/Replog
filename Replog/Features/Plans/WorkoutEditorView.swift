//
//  WorkoutEditorView.swift
//  Replog
//
//  Edit one training day: name, weekday (taken days disabled), exercises, add/remove
//  exercises, delete the workout. Tapping an exercise card opens a native bottom sheet
//  of set steppers (weight/reps/rest). Exercise cards are long-press draggable to
//  reorder, so this is a `List` (the only container with native reordering on iOS 26)
//  styled as the app's cards via `plainListRow`.
//

import SwiftUI
import SwiftData

struct WorkoutEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Environment(PremiumGate.self) private var gate
    @Bindable var workout: Workout
    @Query private var settingsList: [AppSettings]

    @State private var detailItem: PlanItem?
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
            Section { headerRows.plainListRow(top: 8, bottom: 8) }

            Section {
                let items = workout.orderedItems
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ExerciseEditRow(
                        item: item,
                        exercise: catalog.exercise(id: item.exId),
                        // The set sheet is pure editing — there is nothing on it to read that
                        // the row does not already show — so it is gated rather than disabled.
                        onOpen: { openSetSheet(item) },
                        onInfo: { detailRef = ExerciseRef(id: item.exId) },
                        onRemove: { requestRemove(item) }
                    )
                    .plainListRow(top: 8, bottom: 8)
                    .reorderAccessibilityActions(index: index, count: items.count,
                                                 move: requestMoveItems)
                }
                .onMove(perform: reorderHandler)
            }

            Section {
                Group {
                    Button(action: openPicker) {
                        dashedLabel(icon: "plus", title: "Add exercise", color: .accent)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: requestDeleteWorkout) {
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
        .sheet(item: $detailItem) { item in
            ExerciseSetSheet(
                item: item,
                exercise: catalog.exercise(id: item.exId),
                defaultRest: defaultRest,
                onAddSet: { addSet(to: item) },
                onRemoveSet: { removeSet($0, from: item) },
                onChange: { try? context.save() }
            )
        }
    }

    /// The title, weekday picker and description.
    ///
    /// Extracted from `body` because adding the locked banner's conditional pushed the List's
    /// generic type past what the type-checker would solve, and it reported that as an
    /// unrelated ambiguity on the toolbar forty lines further down.
    @ViewBuilder
    private var headerRows: some View {
        // A locked athlete keeps every bit of read access to their own plan; only the controls
        // stop working. Saying so is what keeps that from reading as a bug — a text field that
        // will not focus has no other explanation.
        if gate.isLocked {
            LockedBanner(message: "Read-only. Subscribe to edit this workout.") {
                gate.presentPaywall()
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(workout.plan?.name ?? "Plan").eyebrow()
            TextField("Workout name", text: $workout.name)
                .font(.screenTitle).foregroundStyle(Color.textPrimary)
                .onChange(of: workout.name) { try? context.save() }
                // Bound straight to the model, so a keystroke IS the mutation. There is no
                // later point at which this could be intercepted.
                .disabled(gate.isLocked)
        }

        dayPicker

        // Optional description — below the day pills, above the count line, styled like the
        // count line but editable. Selectable/copyable like any text field.
        TextField("Add a description (optional)", text: $workout.notes, axis: .vertical)
            .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
            .lineLimit(1...6)
            .onChange(of: workout.notes) { try? context.save() }
            .disabled(gate.isLocked)

        Text("\(workout.items.count) exercises · \(workout.setCount) sets · hold to reorder")
            .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
    }

    private var restForAllButton: some View {
        Button(action: openRestSheet) {
            Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.text2)
        }
    }

    /// `nil` while locked, which turns the drag off outright — a reorder is committed by the
    /// system before any handler of ours could refuse it.
    ///
    /// A computed property rather than a `let` inside the `List`'s builder, and a `guard`
    /// rather than a ternary. Both matter: binding an optional function type inside that
    /// builder defeats the type-checker and it blames the toolbar fifty lines away, and
    /// `isLocked ? nil : moveItems` will not promote a method reference to an optional on its
    /// own. Neither failure names the real line. Leave this shape alone.
    private var reorderHandler: ((IndexSet, Int) -> Void)? {
        guard !gate.isLocked else { return nil }
        return moveItems
    }

    // MARK: Gated intents
    //
    // Named rather than inlined as `gate.require { … }` at each call site. Two reasons: the
    // body reads as a list of intents instead of a list of closures, and enough nested
    // closures in one `List` pushed the type-checker into reporting an unrelated ambiguity on
    // the toolbar.

    /// The VoiceOver rotor's Move up/down call their handler directly, so unlike the drag —
    /// which `reorderHandler` switches off outright — they have to be gated here. A rotor
    /// action is not a lesser way to use the app, and it must not be a way around the gate.
    private func requestMoveItems(from source: IndexSet, to destination: Int) {
        gate.require { moveItems(from: source, to: destination) }
    }

    private func openRestSheet() { gate.require { showRestSheet = true } }
    private func openPicker() { gate.require { showPicker = true } }
    private func openSetSheet(_ item: PlanItem) { gate.require { detailItem = item } }
    private func requestRemove(_ item: PlanItem) { gate.require { remove(item) } }
    private func requestDeleteWorkout() { gate.require { deleteWorkout() } }
    private func requestSetExtra() { gate.require { setExtra() } }
    private func requestSetDay(_ day: Weekday) { gate.require { setDay(day) } }

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
                        isSelected: workout.isExtra, disabled: false) { requestSetExtra() }
                ForEach(Weekday.allCases) { day in
                    dayPill(label: day.short, icon: nil,
                            isSelected: !workout.isExtra && workout.day == day,
                            disabled: takenDays.contains(day)) { requestSetDay(day) }
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

    /// Drag-to-reorder the exercise cards.
    private func moveItems(from source: IndexSet, to destination: Int) {
        guard Reordering.apply(from: source, to: destination, in: workout.orderedItems) else { return }
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
        // Bodyweight moves store *added* load, so a fresh set is 0 (pure bodyweight);
        // loaded moves seed 20 kg as before.
        let isBodyweight = catalog.exercise(id: item.exId).map { BodyweightLoad.isBodyweightLoaded($0) } ?? false
        let set = SetTemplate(weightKg: last?.weightKg ?? (isBodyweight ? 0 : 20), reps: last?.reps ?? 10,
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

// MARK: - Exercise card (taps to open the set-editor sheet)

private struct ExerciseEditRow: View {
    let item: PlanItem
    let exercise: Exercise?
    let onOpen: () -> Void
    let onInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 52, cornerRadius: 12)
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
        .padding(14)
        .cardSurface()
        // Tap anywhere on the card (except the two buttons) to open the set-editor sheet.
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
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

// MARK: - Set-editor bottom sheet (weight / reps / rest)

/// Native bottom sheet that slides up to edit one exercise's sets. Dismiss-only via the
/// grabber / swipe-down (edits auto-save through `onChange`), matching the app's other
/// dismiss-only sheets — no "Done" button.
private struct ExerciseSetSheet: View {
    @Bindable var item: PlanItem
    let exercise: Exercise?
    let defaultRest: Int
    let onAddSet: () -> Void
    let onRemoveSet: (SetTemplate) -> Void
    let onChange: () -> Void

    private var effectiveRest: Int { item.restSeconds ?? defaultRest }
    /// A bodyweight movement logs the athlete's own weight — no kg to type. Extra load
    /// (a dip belt, a vest) is optional per set. Detected the same way the live log is.
    private var isBodyweight: Bool { exercise.map { BodyweightLoad.isBodyweightLoaded($0) } ?? false }
    private var isTimedHold: Bool { exercise.map { BodyweightLoad.isTimedHold($0) } ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if isBodyweight {
                    Text("Bodyweight movement — counts your bodyweight; add extra load per set only if you used any.")
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                Divider().padding(.vertical, 12)
                ForEach(Array(item.orderedSets.enumerated()), id: \.element.id) { index, set in
                    SetEditorRow(index: index + 1, template: set,
                                 canRemove: item.sets.count > 1,
                                 isBodyweight: isBodyweight, isTimedHold: isTimedHold,
                                 onRemove: { onRemoveSet(set) }, onChange: onChange)
                }
                Button(action: onAddSet) {
                    HStack(spacing: 5) { Image(systemName: "plus"); Text("Add set") }
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().padding(.vertical, 12)
                restEditor
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 54, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise?.name ?? item.exId).font(.rounded(19, .heavy))
                    .foregroundStyle(Color.textPrimary).lineLimit(2)
                Text("\(item.sets.count) sets · \(exercise?.primaryMuscles.first?.displayName ?? "—")")
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
            }
            Spacer(minLength: 6)
        }
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
}

// MARK: - Single set editor (weight & reps steppers)

private struct SetEditorRow: View {
    let index: Int
    @Bindable var template: SetTemplate
    let canRemove: Bool
    /// A bodyweight movement: no weight to type. The stored `weightKg` is *added* load
    /// only (belt/vest), revealed on demand. Everything else types a plain weight.
    var isBodyweight: Bool = false
    /// A timed hold (plank): the `reps` field is seconds, not reps.
    var isTimedHold: Bool = false
    let onRemove: () -> Void
    let onChange: () -> Void

    /// Whether the optional added-load stepper is showing for a bodyweight set.
    @State private var showAddedWeight = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(index)").font(.rounded(13, .heavy)).foregroundStyle(Color.text3).frame(width: 16)

                // Weight column: always for loaded movements; for bodyweight only once the
                // athlete asks for it (or a previous session already logged added load).
                if !isBodyweight || showAddedWeight || template.weightKg > 0 {
                    column(isBodyweight ? "ADDED (kg)" : "WEIGHT (kg)") {
                        // Editing clears `estimated`: the number is the athlete's now, not a
                        // computed seed — which also stops a later session overwriting it.
                        NumericStepperField(display: weightText, keyboard: .decimalPad,
                                            onMinus: { template.weightKg = max(0, template.weightKg - 2.5); template.markEdited(); onChange() },
                                            onPlus: { template.weightKg += 2.5; template.markEdited(); onChange() },
                                            onCommit: { if let kg = Formulas.parseWeightKg($0, units: .kg) { template.weightKg = kg; template.markEdited(); onChange() } })
                    }
                }
                column(isTimedHold ? "SECONDS" : "REPS") {
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

            // Bodyweight, no added load yet: offer to add some (dip belt, vest).
            if isBodyweight, !showAddedWeight, template.weightKg == 0 {
                Button { withAnimation(.smooth) { showAddedWeight = true } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12, weight: .bold))
                        Text("Add weight").font(.rounded(12, .heavy))
                    }
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("For a dip belt or weighted vest")
            }
        }
        .padding(.vertical, 6)
    }

    private func column<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private var weightText: String {
        template.weightKg == template.weightKg.rounded() ? String(Int(template.weightKg)) : String(format: "%.1f", template.weightKg)
    }
}
