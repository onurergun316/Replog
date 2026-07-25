//
//  ExerciseLogCard.swift
//  Replog
//
//  One exercise card in the active workout: a coach-suggestion banner (ProgressionEngine),
//  set rows with trend arrows, a tap-to-edit inline stepper editor, swipe-to-delete,
//  and Add set.
//

import SwiftUI

struct ExerciseLogCard: View {
    @Bindable var exercise: SessionExercise
    let name: String
    let muscle: String
    let photo: ExercisePhoto?
    let units: Units
    /// True when the movement is loaded by the athlete's own bodyweight. The weight
    /// column becomes a "BW" chip and typing a load is optional — the stepper in the
    /// expanded editor is for *added* weight only (dip belt, vest).
    var isBodyweight: Bool = false
    /// True when the logged count is seconds rather than reps (plank and friends).
    var isTimedHold: Bool = false
    @Binding var expandedSetID: UUID?
    let onCheck: (LoggedSet) -> Void
    let onInfo: () -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (LoggedSet) -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if let suggestion = exercise.suggestion, !exercise.suggestionDismissed, !exercise.isDone {
                SuggestionBanner(
                    recommendation: suggestion,
                    onApply: {
                        withAnimation(.snappy) { exercise.applySuggestion() }
                        onChange()
                    },
                    onDismiss: {
                        withAnimation(.snappy) { exercise.suggestionDismissed = true }
                        onChange()
                    }
                )
                .padding(.top, 12)
            }
            columnHeader
            ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                SetLogRow(
                    index: index + 1, set: set, units: units,
                    isBodyweight: isBodyweight, isTimedHold: isTimedHold,
                    isEditing: expandedSetID == set.id,
                    onToggleEdit: { toggleEdit(set) },
                    onCheck: { onCheck(set) },
                    onDelete: { onDeleteSet(set) },
                    onChange: onChange
                )
            }
            Button(action: onAddSet) {
                HStack(spacing: 5) { Image(systemName: "plus"); Text("Add set") }
                    .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(exercise.isDone ? Color.up.opacity(0.10) : Color.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(exercise.isDone ? Color.up.opacity(0.4) : Color.border, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(photo: photo, size: 46, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text("\(exercise.sets.count) sets · \(muscle)").font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
            }
            Spacer(minLength: 8)
            Button(action: onInfo) {
                Image(systemName: "info.circle").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.text3)
            }
            .buttonStyle(.plain)
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("SET").frame(width: 30, alignment: .leading)
            Text(isBodyweight ? (isTimedHold ? "HOLD" : "REPS") : "WEIGHT & REPS")
            Spacer()
            Text("RPE")
        }
        .font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
        .padding(.top, 12).padding(.bottom, 6)
    }

    private func toggleEdit(_ set: LoggedSet) {
        withAnimation(.snappy) { expandedSetID = expandedSetID == set.id ? nil : set.id }
    }
}

// MARK: - Coach suggestion banner

/// The ProgressionEngine's next-session prescription for this lift. Purely advisory:
/// "Apply" copies it onto the not-yet-logged sets, "x" dismisses it for this session,
/// and it never overwrites anything the user has already logged.
private struct SuggestionBanner: View {
    let recommendation: ProgressionRecommendation
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .heavy))
                Text("Coach: \(recommendation.action.displayName)")
                    .font(.rounded(12, .heavy))
                Spacer(minLength: 8)
                Button(action: onApply) {
                    Text("Apply").font(.rounded(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.text3)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.surface2))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(tint)
            Text(recommendation.reason)
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }

    private var tint: Color {
        switch recommendation.action {
        case .increaseLoad, .increaseReps: return Color.up
        case .hold:                        return Color.accent
        case .deload:                      return Color.down
        }
    }

    private var symbol: String {
        switch recommendation.action {
        case .increaseLoad: return "arrow.up.circle.fill"
        case .increaseReps: return "plus.circle.fill"
        case .hold:         return "equal.circle.fill"
        case .deload:       return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Set row

private struct SetLogRow: View {
    let index: Int
    @Bindable var set: LoggedSet
    let units: Units
    var isBodyweight: Bool = false
    var isTimedHold: Bool = false
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onCheck: () -> Void
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var dragOffset: CGFloat = 0
    /// Whether the added-load stepper has been revealed on a bodyweight movement.
    @State private var showAddedWeight = false
    private let revealWidth: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                // Delete affordance, only visible while swiped open. Clipped with the row so
                // it never bleeds past the rounded corner.
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.white)
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.down)
                }
                .buttonStyle(.plain)
                .opacity(dragOffset < -4 ? 1 : 0)

                rowContent
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(set.done ? Color.up.opacity(0.12) : Color.surface2))
                    .offset(x: dragOffset)
                    .gesture(swipe)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if isEditing { inlineEditor }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: set.done)
        .sensoryFeedback(.success, trigger: set.done) { _, done in done } // haptic only when marked done
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Text("\(index)").font(.rounded(13, .heavy)).foregroundStyle(Color.text3).frame(width: 22)

            // Load. A bodyweight movement has no weight to type, so it reads as a "BW"
            // chip and only mentions kilograms once a belt or vest is actually logged.
            if isBodyweight {
                valueButton {
                    HStack(spacing: 3) {
                        Text("BW")
                            .font(.rounded(11, .black)).foregroundStyle(Color.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentSoft))
                            .strikethrough(set.done, color: Color.up)
                        if set.weightKg > 0 {
                            Text("+\(Formulas.formatWeight(kg: set.weightKg, units: units))")
                                .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                .tabularNumbers()
                                .strikethrough(set.done, color: Color.up)
                        }
                    }
                }
                .accessibilityLabel(set.weightKg > 0
                                    ? "bodyweight plus \(Formulas.formatWeight(kg: set.weightKg, units: units))"
                                    : "bodyweight")
            } else {
                // Weight + trend — struck through when the set is done.
                valueButton {
                    HStack(spacing: 2) {
                        Text(Formulas.formatWeight(kg: set.weightKg, units: units, includeUnit: false))
                            .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                            .strikethrough(set.done, color: Color.up)
                        Text(units.label).font(.rounded(9, .bold)).foregroundStyle(Color.text3)
                        if !set.done { TrendArrow(trend: set.weightTrend) }
                        // A computed starting estimate — flagged until a finished session
                        // replaces it with the athlete's own logged numbers.
                        if !set.done, set.estimated {
                            Text("est")
                                .font(.rounded(8, .black)).foregroundStyle(Color.accent)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentSoft))
                                .accessibilityLabel("suggested starting weight")
                        }
                    }
                }
                Text("×").font(.rounded(13, .bold)).foregroundStyle(Color.text3)
            }
            // Reps — or seconds, for a hold.
            valueButton {
                HStack(spacing: 2) {
                    Text("\(set.reps)").font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                        .strikethrough(set.done, color: Color.up)
                    Text(isTimedHold ? "sec" : "reps")
                        .font(.rounded(9, .bold)).foregroundStyle(Color.text3)
                    if !set.done { TrendArrow(trend: set.repsTrend) }
                }
            }
            Spacer()
            valueButton {
                Text("RPE \(set.rpe)").font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
            }
            .opacity(set.done ? 0.5 : 1)
            // Check circle
            Button(action: onCheck) {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundStyle(set.done ? Color.up : Color.text3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .opacity(set.done ? 0.78 : 1)
    }

    private func valueButton<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Button(action: onToggleEdit) { content() }.buttonStyle(.plain)
    }

    private var inlineEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Bodyweight movements keep the load column out of the way until the
                // athlete asks for it — most sets are just reps.
                if !isBodyweight || showAddedWeight || set.weightKg > 0 {
                    editorColumn(title: isBodyweight ? "ADDED (\(units.label))" : "WEIGHT (\(units.label))",
                                 value: Formulas.formatWeight(kg: set.weightKg, units: units, includeUnit: false),
                                 keyboard: .decimalPad,
                                 onMinus: { set.weightKg = max(0, set.weightKg - Formulas.weightStepKg(units: units)); onChange() },
                                 onPlus: { set.weightKg += Formulas.weightStepKg(units: units); onChange() },
                                 onCommit: { raw in
                                     if let kg = Formulas.parseWeightKg(raw, units: units) { set.weightKg = kg; onChange() }
                                 })
                }
                editorColumn(title: isTimedHold ? "SECONDS" : "REPS", value: "\(set.reps)",
                             keyboard: .numberPad,
                             onMinus: { set.reps = max(1, set.reps - 1); onChange() },
                             onPlus: { set.reps += 1; onChange() },
                             onCommit: { raw in
                                 if let reps = Formulas.parseReps(raw) { set.reps = reps; onChange() }
                             })
            }
            if isBodyweight, !showAddedWeight, set.weightKg == 0 {
                Button { withAnimation(.snappy) { showAddedWeight = true } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12, weight: .bold))
                        Text("Add weight").font(.rounded(13, .heavy))
                    }
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("For a dip belt or weighted vest")
            }
            VStack(spacing: 6) {
                Text("RPE — how hard did it feel?").font(.rounded(11, .bold)).foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(6...10, id: \.self) { value in
                        Button { set.rpe = value; onChange() } label: {
                            Text("\(value)").font(.rounded(14, .heavy))
                                .foregroundStyle(set.rpe == value ? .white : Color.text2)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(set.rpe == value ? Color.accent : Color.surface2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2.opacity(0.6)))
        .padding(.top, 6)
    }

    private func editorColumn(title: String, value: String, keyboard: UIKeyboardType,
                             onMinus: @escaping () -> Void, onPlus: @escaping () -> Void,
                             onCommit: @escaping (String) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
            NumericStepperField(display: value, keyboard: keyboard,
                                onMinus: onMinus, onPlus: onPlus, onCommit: onCommit)
        }
        .frame(maxWidth: .infinity)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in if v.translation.width < 0 { dragOffset = max(-revealWidth, v.translation.width) } }
            .onEnded { v in withAnimation(.snappy) { dragOffset = v.translation.width < -40 ? -revealWidth : 0 } }
    }
}
