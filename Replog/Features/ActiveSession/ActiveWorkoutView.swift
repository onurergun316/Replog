//
//  ActiveWorkoutView.swift
//  Replog
//
//  The core logging loop: running timer, optional in-header rest timer, set rows with
//  finance-style trend arrows, inline editors, swipe-to-delete, spring reorder of
//  finished exercises, and Finish.
//
//  Finish ends here: badges and debrief insights are handed to `onFinished` and this screen
//  dismisses. It does not celebrate anything itself — finishing deletes the session this
//  view is presented from, so it is gone before an overlay could be seen (`SessionCompletion`).
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
    /// Handed everything the finished session earned, for whoever is still on screen to
    /// celebrate. Finishing deletes the session and this view is presented *from* that
    /// session, so nothing raised here would survive long enough to be seen — see
    /// `SessionCompletion`.
    var onFinished: (_ badges: [Badge], _ insights: [CoachInsight]) -> Void = { _, _ in }

    @State private var expandedSetID: UUID?
    @State private var restTimer = RestTimerModel()
    @State private var detailRef: ExerciseRef?
    @State private var showFinishConfirm = false
    @State private var showCelebration = false
    @State private var didCelebrate = false
    @State private var showAddExercise = false
    /// What this session added beyond the plan, held while the athlete decides whether to
    /// keep it. Non-nil means the "save to the plan?" dialog is up.
    @State private var pendingAdditions: TemplateWriteBack.Additions?

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
                        let entry = catalog.exercise(id: exercise.exId)
                        ExerciseLogCard(
                            exercise: exercise,
                            name: entry?.name ?? exercise.exId,
                            muscle: entry?.primaryMuscles.first?.displayName ?? "",
                            photo: entry?.photos.first,
                            units: settings.units,
                            isBodyweight: entry.map { BodyweightLoad.isBodyweightLoaded($0) } ?? false,
                            isTimedHold: entry.map { BodyweightLoad.isTimedHold($0) } ?? false,
                            expandedSetID: $expandedSetID,
                            onCheck: { toggle($0, in: exercise) },
                            onInfo: { detailRef = ExerciseRef(id: exercise.exId) },
                            onAddSet: { addSet(to: exercise) },
                            onDeleteSet: { deleteSet($0, from: exercise) },
                            onChange: { try? context.save() }
                        )
                        .id(exercise.id)
                    }
                    addExerciseButton
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
        .sheet(isPresented: $showAddExercise) {
            AddExercisePicker(existingIDs: Set(session.exercises.map(\.exId))) { exId in
                addExercise(exId)
            }
        }
        .confirmationDialog("Save to your plan?", isPresented: showingAdditionsPrompt,
                            titleVisibility: .visible) {
            Button("Save to plan") { finish(saveAdditions: true) }
            Button("Just this time") { finish(saveAdditions: false) }
        } message: {
            Text(additionsPromptMessage)
        }
        .confirmationDialog("Finish workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish anyway", role: .destructive) { requestFinish() }
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
                    onFinish: { showCelebration = false; requestFinish() },
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

    /// Adding a movement the plan never prescribed is a normal thing to do at a gym: a rack
    /// is busy, or there is time for one more. It stays a fact about this session unless the
    /// athlete says otherwise at Finish.
    private var addExerciseButton: some View {
        Button { showAddExercise = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13, weight: .black))
                Text("Add exercise").font(.rounded(15, .heavy))
            }
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(Color.border)
            )
        }
        .buttonStyle(.plain)
    }

    private var showingAdditionsPrompt: Binding<Bool> {
        Binding(get: { pendingAdditions != nil },
                set: { if !$0 { pendingAdditions = nil } })
    }

    private var additionsPromptMessage: String {
        guard let additions = pendingAdditions else { return "" }
        return "You did \(additions.summary) more than \(session.name) prescribes. "
            + "Save that to the plan for next time, or keep the plan as it is?"
    }

    private var finishWarningMessage: String {
        let remaining = max(0, session.totalSets - session.completedSets)
        var msg = "You still have \(remaining) set\(remaining == 1 ? "" : "s") to go. "
        if profile.streak > 0 {
            msg += "Finishing now won't count this workout, and you'll lose your "
                + "\(profile.streak)-day streak. "
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

    /// Adds a movement to the live session only. It becomes part of the plan only if the
    /// athlete opts in at Finish. The opening set starts from what this plan last saw for
    /// the movement, so it is not a blank 20 kg guess.
    private func addExercise(_ exId: String) {
        guard !session.exercises.contains(where: { $0.exId == exId }) else { return }
        let exercise = SessionExercise(exId: exId,
                                       order: Reordering.nextOrder(after: session.exercises))
        exercise.session = session
        context.insert(exercise)

        let previous = context.history(forExercise: exId, inPlan: session.planId).last?.sets.first
        let isBodyweight = catalog.exercise(id: exId).map { BodyweightLoad.isBodyweightLoaded($0) } ?? false
        let set = LoggedSet(weightKg: previous?.w ?? (isBodyweight ? 0 : 20),
                            reps: previous?.r ?? 10, rpe: 8,
                            prevWeight: previous?.w, prevReps: previous?.r, order: 0)
        set.exercise = exercise
        context.insert(set)
        try? context.save()
    }

    private func addSet(to exercise: SessionExercise) {
        let last = exercise.orderedSets.last
        // Bodyweight moves store *added* load, so a fresh set is 0 (pure bodyweight).
        let isBodyweight = catalog.exercise(id: exercise.exId).map { BodyweightLoad.isBodyweightLoaded($0) } ?? false
        let set = LoggedSet(weightKg: last?.weightKg ?? (isBodyweight ? 0 : 20), reps: last?.reps ?? 10, rpe: last?.rpe ?? 8,
                            prevWeight: last?.prevWeight, prevReps: last?.prevReps,
                            order: Reordering.nextOrder(after: exercise.sets))
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

    /// Finishing, gated on one question: did this session do more than the plan asked?
    /// Only a fully complete workout writes back at all, so only that can have additions
    /// worth keeping.
    private func requestFinish() {
        let additions = session.isComplete
            ? TemplateWriteBack.additions(for: session, context: context)
            : TemplateWriteBack.Additions()
        if additions.isEmpty {
            finish(saveAdditions: false)
        } else {
            pendingAdditions = additions
        }
    }

    private func finish(saveAdditions: Bool) {
        pendingAdditions = nil
        // Capture the outcome (PRs judged vs prior best) BEFORE history is written.
        let outcome = CoachContextBuilder.sessionOutcome(from: session, context: context, catalog: catalog)
        let deloadRule = sourceProgramDeloadRule()
        // Finishing deletes the session, so anything a badge wants to remember about what
        // was being trained has to be read off it first.
        let planName = session.planName.isEmpty ? nil : session.planName
        let workoutName = session.name.isEmpty ? nil : session.name

        SessionFinisher.finish(session, profile: profile, context: context,
                               saveAdditions: saveAdditions)

        // Build the debrief from the now-updated store and record its durable insights.
        let ctx = CoachContextBuilder.debriefContext(
            outcome: outcome, profile: profile, settings: settings,
            programDeloadRule: deloadRule, context: context, catalog: catalog)
        let insights = CoachEngine.insights(ctx)
        CoachContextBuilder.recordDebrief(insights, context: context)
        try? context.save()

        // Today's session is done — re-plan notifications (clears today's streak-risk nudge).
        NotificationCoordinator.refresh(context: context)

        // Anything this session just earned, stamped with what was being trained.
        let badges = BadgeAwarding.award(context: context, catalog: catalog,
                                         planName: planName, workoutName: workoutName)
        try? context.save()

        // Handed over rather than shown here: this screen is about to be torn down with the
        // session it was presented from. `RootView` plays the badge, then the debrief, once
        // the cover is out of the way.
        onFinished(badges, insights)
        dismiss()
    }

    /// The deload rule of the program this session's workout belongs to, if program-driven.
    private func sourceProgramDeloadRule() -> String? {
        guard let workoutId = session.workoutId else { return nil }
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        let rule = plans.first { $0.workouts.contains { $0.id == workoutId } }?.progressionDeload
        return (rule?.isEmpty ?? true) ? nil : rule
    }
}
