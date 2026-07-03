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
    @State private var restTimer = RestTimerModel()
    @State private var detailRef: ExerciseRef?
    @State private var showFinishConfirm = false
    @State private var showCelebration = false
    @State private var didCelebrate = false
    @State private var debriefInsights: [CoachInsight] = []
    @State private var showDebrief = false

    private var profile: UserProfile { profiles.first ?? context.userProfile() }
    private var settings: AppSettings { settingsList.first ?? context.appSettings() }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !session.readinessNote.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accent)
                    Text(session.readinessNote)
                        .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentSoft)
            }
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
            .scrollDismissesKeyboard(.immediately)
        }
        .hideKeyboardOnTap()
        .background(Color.bg.ignoresSafeArea())
        .sheet(item: $detailRef) { ref in
            NavigationStack { ExerciseDetailView(exId: ref.id, showProgress: true) }
        }
        .sheet(isPresented: $showDebrief, onDismiss: { dismiss() }) {
            NavigationStack { CoachDebriefView(insights: debriefInsights) }
        }
        .confirmationDialog("Finish workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish anyway", role: .destructive) { finish() }
            Button("Save for later") { close() }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text(finishWarningMessage)
        }
        .overlay {
            if showCelebration {
                CelebrationOverlay(
                    sets: session.completedSets,
                    exercises: session.exercises.count,
                    onFinish: { showCelebration = false; finish() },
                    onKeepGoing: { withAnimation(.snappy) { showCelebration = false } }
                )
                .transition(.opacity)
            }
        }
        // Auto-celebrate the moment the final set is checked (Duolingo-style).
        .onChange(of: session.isComplete) { _, complete in
            if complete && !didCelebrate {
                didCelebrate = true
                withAnimation(.snappy) { showCelebration = true }
            } else if !complete {
                didCelebrate = false
            }
        }
        .onAppear {
            // Handles resuming a session that is already fully complete.
            if session.isComplete && !didCelebrate {
                didCelebrate = true
                showCelebration = true
            }
        }
    }

    private var finishWarningMessage: String {
        let remaining = max(0, session.totalSets - session.completedSets)
        var msg = "You still have \(remaining) set\(remaining == 1 ? "" : "s") to go. "
        if profile.streak > 0 {
            msg += "Finishing now won't count this workout, and you'll lose your "
                + "\(profile.streak)-workout streak. "
        } else {
            msg += "Finishing now won't count this workout toward your streak. "
        }
        msg += "Save it for later to pick up where you left off."
        return msg
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                circleButton("xmark") { close() }
                Spacer()
                VStack(spacing: 1) {
                    Text(session.name).font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(elapsedText).font(.rounded(13, .bold)).foregroundStyle(Color.accent).tabularNumbers()
                    }
                }
                Spacer()
                circleButton("timer") { restTimer.start(seconds: settings.restSeconds) }
                Button { attemptFinish() } label: {
                    Text("Finish").font(.rounded(14, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.accent))
                }
                .buttonStyle(.plain)
            }

            progressBar

            if restTimer.isRunning { restBar }
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
            let remaining = restTimer.remaining(at: context.date)
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.accent.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: restTimer.fraction(at: context.date))
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                Text(timeString(remaining)).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).tabularNumbers()
                Spacer()
                restButton("−15") { restTimer.adjust(-15) }
                restButton("+15") { restTimer.adjust(15) }
                restButton("Skip") { restTimer.skip() }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentSoft))
            .onChange(of: remaining) { _, new in if new == 0 { restTimer.skip() } }
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color.text2)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private func restButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular.tint(Color.surface), in: .capsule)
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
        let justCompleted = set.done
        // Maintain doneOrder so finished exercises sort to the bottom in completion order.
        if exercise.isDone {
            let maxOrder = session.exercises.map(\.doneOrder).max() ?? -1
            exercise.doneOrder = maxOrder + 1
        } else {
            exercise.doneOrder = -1
        }
        // (Re)start the rest timer on every set completion — when auto-start is on, or
        // whenever a timer is already running (so checking a set resets the active
        // countdown). Uses this exercise's own rest duration when set, else the app default.
        if justCompleted && (settings.restTimerAuto || restTimer.isRunning) {
            restTimer.start(seconds: exercise.restSeconds ?? settings.restSeconds)
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

    /// Closes the cover but keeps the session: it's paused & persisted, continuable from Today.
    private func close() {
        session.isOpen = false
        try? context.save()
        dismiss()
    }

    private func attemptFinish() {
        if session.isComplete {
            withAnimation(.snappy) { showCelebration = true }
        } else {
            showFinishConfirm = true
        }
    }

    private func finish() {
        // Capture the outcome (PRs judged vs prior best) BEFORE history is written.
        let outcome = CoachContextBuilder.sessionOutcome(from: session, context: context, catalog: catalog)
        let deloadRule = sourceProgramDeloadRule()

        SessionFinisher.finish(session, profile: profile, context: context)

        // Build the debrief from the now-updated store and record its durable insights.
        let ctx = CoachContextBuilder.debriefContext(
            outcome: outcome, profile: profile, settings: settings,
            programDeloadRule: deloadRule, context: context, catalog: catalog)
        let insights = CoachEngine.insights(ctx)
        CoachContextBuilder.recordDebrief(insights, context: context)
        try? context.save()

        if insights.isEmpty {
            dismiss()
        } else {
            debriefInsights = insights
            showDebrief = true   // dismissing the debrief dismisses the workout
        }
    }

    /// The deload rule of the program this session's workout belongs to, if program-driven.
    private func sourceProgramDeloadRule() -> String? {
        guard let workoutId = session.workoutId else { return nil }
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        let rule = plans.first { $0.workouts.contains { $0.id == workoutId } }?.progressionDeload
        return (rule?.isEmpty ?? true) ? nil : rule
    }
}
