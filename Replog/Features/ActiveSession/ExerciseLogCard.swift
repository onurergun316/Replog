//
//  ExerciseLogCard.swift
//  Replog
//
//  One exercise card in the active workout: set rows with trend arrows, a tap-to-edit
//  inline stepper editor, swipe-to-delete, and Add set.
//

import SwiftUI

struct ExerciseLogCard: View {
    @Bindable var exercise: SessionExercise
    let name: String
    let muscle: String
    let imageName: String?
    let units: Units
    @Binding var expandedSetID: UUID?
    let onCheck: (LoggedSet) -> Void
    let onInfo: () -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (LoggedSet) -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            columnHeader
            ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                SetLogRow(
                    index: index + 1, set: set, units: units,
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
        HStack(spacing: 12) {
            ExerciseImageView(resourceName: imageName, cornerRadius: 10).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text("\(exercise.sets.count) sets · \(muscle)").font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
            }
            Spacer()
            Button(action: onInfo) {
                Image(systemName: "info.circle").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.text3)
            }
            .buttonStyle(.plain)
        }
    }

    private var columnHeader: some View {
        HStack {
            Text("SET").frame(width: 30, alignment: .leading)
            Text("WEIGHT & REPS")
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

// MARK: - Set row

private struct SetLogRow: View {
    let index: Int
    @Bindable var set: LoggedSet
    let units: Units
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onCheck: () -> Void
    let onDelete: () -> Void
    let onChange: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                // Delete affordance revealed by swiping left.
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.white)
                        .frame(width: 56, height: 44).background(Color.down)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                rowContent
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(set.done ? Color.up.opacity(0.12) : Color.surface2))
                    .offset(x: dragOffset)
                    .gesture(swipe)
            }
            if isEditing { inlineEditor }
        }
        .padding(.vertical, 4)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Text("\(index)").font(.rounded(13, .heavy)).foregroundStyle(Color.text3).frame(width: 22)

            // Weight + trend
            valueButton {
                HStack(spacing: 2) {
                    Text(Formulas.formatWeight(kg: set.weightKg, units: units, includeUnit: false))
                        .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                    Text(units.label).font(.rounded(9, .bold)).foregroundStyle(Color.text3)
                    TrendArrow(trend: set.weightTrend)
                }
            }
            Text("×").font(.rounded(13, .bold)).foregroundStyle(Color.text3)
            // Reps + trend
            valueButton {
                HStack(spacing: 2) {
                    Text("\(set.reps)").font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                    Text("reps").font(.rounded(9, .bold)).foregroundStyle(Color.text3)
                    TrendArrow(trend: set.repsTrend)
                }
            }
            Spacer()
            valueButton {
                Text("RPE \(set.rpe)").font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
            }
            // Check circle
            Button(action: onCheck) {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundStyle(set.done ? Color.up : Color.text3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func valueButton<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Button(action: onToggleEdit) { content() }.buttonStyle(.plain)
    }

    private var inlineEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                editorColumn(title: "WEIGHT (\(units.label))",
                             value: Formulas.formatWeight(kg: set.weightKg, units: units, includeUnit: false),
                             onMinus: { set.weightKg = max(0, set.weightKg - Formulas.weightStepKg(units: units)); onChange() },
                             onPlus: { set.weightKg += Formulas.weightStepKg(units: units); onChange() })
                editorColumn(title: "REPS", value: "\(set.reps)",
                             onMinus: { set.reps = max(1, set.reps - 1); onChange() },
                             onPlus: { set.reps += 1; onChange() })
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

    private func editorColumn(title: String, value: String,
                             onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.rounded(10, .heavy)).foregroundStyle(Color.text3)
            StepperControl(value: value, onMinus: onMinus, onPlus: onPlus)
        }
        .frame(maxWidth: .infinity)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in if v.translation.width < 0 { dragOffset = max(-64, v.translation.width) } }
            .onEnded { v in withAnimation(.snappy) { dragOffset = v.translation.width < -40 ? -64 : 0 } }
    }
}
