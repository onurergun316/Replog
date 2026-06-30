//
//  ActiveWorkoutView.swift
//  Replog
//
//  The core logging loop: running timer, optional in-header rest timer, set rows with
//  finance-style trend arrows, inline editors, swipe-to-delete, spring reorder of
//  finished exercises, and Finish.
//

import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var profiles: [UserProfile]
    @Query private var settingsList: [AppSettings]
    @Bindable var session: ActiveSession

    @State private var expandedSetID: UUID?
    @State private var restEndDate: Date?
    @State private var restTotal: Int = 90
    @State private var detailRef: ExerciseRef?

    private var profile: UserProfile { profiles.first ?? context.userProfile() }
    private var settings: AppSettings { settingsList.first ?? context.appSettings() }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(session.orderedExercises) { exercise in
                        ExerciseLogCard(
                            exercise: exercise,
                            name: catalog.exercise(id: exercise.exId)?.name ?? exercise.exId,
                            muscle: catalog.exercise(id: exercise.exId)?.primaryMuscles.first?.displayName ?? "",
                            imageName: catalog.exercise(id: exercise.exId)?.imageResourceNames.first,
                            units: settings.units,
                            expandedSetID: $expandedSetID,
                            onCheck: { toggle($0, in: exercise) },
                            onInfo: { detailRef = ExerciseRef(id: exercise.exId) },
                            onAddSet: { addSet(to: exercise) },
                            onDeleteSet: { deleteSet($0, from: exercise) },
                            onChange: { try? context.save() }
                        )
                        .id(exercise.id)
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: session.orderedExercises.map(\.id))
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .sheet(item: $detailRef) { ref in
            NavigationStack { ExerciseDetailView(exId: ref.id, showProgress: true) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                circleButton("xmark") { dismiss() }
                Spacer()
                VStack(spacing: 1) {
                    Text(session.name).font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(elapsedText).font(.rounded(13, .bold)).foregroundStyle(Color.accent).tabularNumbers()
                    }
                }
                Spacer()
                circleButton("timer") { startRest() }
                Button { finish() } label: {
                    Text("Finish").font(.rounded(14, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.accent))
                }
                .buttonStyle(.plain)
            }

            progressBar

            if restEndDate != nil { restBar }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background(Color.surface.ignoresSafeArea(edges: .top))
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2)
                    Capsule().fill(Color.accent)
                        .frame(width: geo.size.width * fractionComplete)
                }
            }
            .frame(height: 6)
            Text("\(session.completedSets) of \(session.totalSets) sets complete")
                .font(.rounded(11, .heavy)).foregroundStyle(Color.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var restBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((restEndDate ?? context.date).timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.accent.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: restTotal > 0 ? CGFloat(remaining) / CGFloat(restTotal) : 0)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                Text(timeString(remaining)).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                Spacer()
                restButton("−15") { adjustRest(-15) }
                restButton("+15") { adjustRest(15) }
                restButton("Skip") { restEndDate = nil }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentSoft))
            .onChange(of: remaining) { _, new in if new == 0 { restEndDate = nil } }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.text2)
                .frame(width: 36, height: 36).background(Circle().fill(Color.surface2))
        }
        .buttonStyle(.plain)
    }

    private func restButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.surface))
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived

    private var fractionComplete: CGFloat {
        session.totalSets == 0 ? 0 : CGFloat(session.completedSets) / CGFloat(session.totalSets)
    }

    private var elapsedText: String {
        timeString(Int(Date().timeIntervalSince(session.startedAt)))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Actions

    private func toggle(_ set: LoggedSet, in exercise: SessionExercise) {
        set.done.toggle()
        // Maintain doneOrder so finished exercises sort to the bottom in completion order.
        if exercise.isDone {
            let maxOrder = session.exercises.map(\.doneOrder).max() ?? -1
            exercise.doneOrder = maxOrder + 1
            if settings.restTimerAuto { startRest() }
        } else {
            exercise.doneOrder = -1
        }
        try? context.save()
    }

    private func addSet(to exercise: SessionExercise) {
        let last = exercise.orderedSets.last
        let set = LoggedSet(weightKg: last?.weightKg ?? 20, reps: last?.reps ?? 10, rpe: last?.rpe ?? 8,
                            prevWeight: last?.prevWeight, prevReps: last?.prevReps, order: exercise.sets.count)
        set.exercise = exercise
        context.insert(set)
        try? context.save()
    }

    private func deleteSet(_ set: LoggedSet, from exercise: SessionExercise) {
        context.delete(set)
        try? context.save()
    }

    private func startRest() {
        restTotal = settings.restSeconds
        restEndDate = Date().addingTimeInterval(TimeInterval(settings.restSeconds))
    }

    private func adjustRest(_ delta: Int) {
        guard let end = restEndDate else { return }
        restTotal = max(15, restTotal + delta)
        restEndDate = end.addingTimeInterval(TimeInterval(delta))
    }

    private func finish() {
        SessionFinisher.finish(session, profile: profile, context: context)
        dismiss()
    }
}
