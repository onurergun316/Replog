//
//  PlanDetailView.swift
//  Replog
//
//  A plan's workouts: editable name, per-workout cards with Start, add a workout on
//  a free weekday, delete the plan. Cards are long-press draggable to reorder — the
//  three sections keep that drag visually clamped to the workouts.
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var settingsList: [AppSettings]
    @Bindable var plan: Plan
    @State private var showRestSheet = false
    @State private var showProgram = false
    /// Bumped on every committed drag, purely to drive the confirmation haptic.
    @State private var moves = 0

    private var defaultRest: Int { (settingsList.first ?? context.appSettings()).restSeconds }

    /// The library program this plan was generated from, if any.
    private var sourceProgram: WorkoutProgram? {
        plan.programId.isEmpty ? nil : ProgramCatalog.shared.program(id: plan.programId)
    }

    var body: some View {
        List {
            Section {
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan").eyebrow()
                        TextField("Plan name", text: $plan.name)
                            .font(.screenTitle).foregroundStyle(Color.textPrimary)
                            .onChange(of: plan.name) { try? context.save() }
                    }
                    Text("\(plan.workouts.count) workouts · \(plan.exerciseCount) exercises · hold to reorder · swipe to delete")
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                    if let program = sourceProgram {
                        Button { showProgram = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "book.pages.fill")
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("About this program")
                                        .font(.rounded(14, .heavy)).foregroundStyle(Color.textPrimary)
                                    Text(program.name)
                                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text2).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.text3)
                            }
                            .padding(12).cardSurface()
                        }
                        .buttonStyle(.plain)
                    }
                    SectionHeader(title: "Workouts")
                }
                .plainListRow()
            }

            Section {
                let workouts = plan.orderedWorkouts
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    ZStack {
                        WorkoutCard(workout: workout, catalog: catalog) { start(workout) }
                        NavigationLink(value: workout) { EmptyView() }.opacity(0) // hides the List chevron
                    }
                    .plainListRow()
                    .reorderAccessibilityActions(index: index, count: workouts.count, move: moveWorkouts)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleteWorkout(workout) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveWorkouts)
            }

            Section {
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
        }
        .listStyle(.plain)
        .listSectionSpacing(0)          // the three sections only scope the drag, not the rhythm
        .reorderCommitFeedback(trigger: moves)
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProgram) {
            if let program = sourceProgram {
                NavigationStack {
                    ProgramDetailView(program: program, showsDoneButton: true)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRestSheet = true } label: {
                    Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.text2)
                }
            }
        }
        .sheet(isPresented: $showRestSheet) {
            SetRestSheet(title: "Rest for whole plan", initialSeconds: defaultRest) { applyRestToPlan($0) }
        }
    }

    private func applyRestToPlan(_ seconds: Int?) {
        for workout in plan.workouts {
            for item in workout.items { item.restSeconds = seconds }
        }
        try? context.save()
    }

    /// Drag-to-reorder: renumbers every workout's `order`, leaving each card's weekday
    /// alone — the drag sets the plan's reading order, not the schedule.
    private func moveWorkouts(from source: IndexSet, to destination: Int) {
        guard Reordering.apply(from: source, to: destination, in: plan.orderedWorkouts) else { return }
        try? context.save()
        moves += 1
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
                Pill(text: workout.slotLabel, style: .accentSoft)
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
                ExerciseFilmStrip(items: workout.orderedItems, catalog: catalog)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// An even "35 mm film strip" of exercise photos: equal-size frames, equal gaps,
/// filling the card width, with a "+N" tail when the workout has more exercises.
struct ExerciseFilmStrip: View {
    let items: [PlanItem]
    let catalog: ExerciseCatalog
    var maxFrames: Int = 5
    var height: CGFloat = 46
    var cornerRadius: CGFloat = 8

    private var shown: [PlanItem] { Array(items.prefix(maxFrames)) }
    private var overflow: Int { max(0, items.count - maxFrames) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                let isLast = idx == shown.count - 1
                ExerciseImageView(resourceName: catalog.exercise(id: item.exId)?.imageResourceNames.first,
                                  cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        if isLast && overflow > 0 {
                            ZStack {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(.black.opacity(0.55))
                                Text("+\(overflow)").font(.rounded(15, .black)).foregroundStyle(.white)
                            }
                        }
                    }
            }
        }
    }
}
