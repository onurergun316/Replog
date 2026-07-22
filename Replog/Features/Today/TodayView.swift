//
//  TodayView.swift
//  Replog
//
//  The daily hub: greeting + streak, week strip, today's workout hero, a scroller
//  of other workouts to run as extras, quick stats, and the latest PR.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query private var profiles: [UserProfile]
    @Query private var history: [HistoryEntry]
    @Query private var activeSessions: [ActiveSession]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @Query private var settingsRows: [AppSettings]

    @State private var path = NavigationPath()
    @State private var selectedStat: StatKind?
    @State private var showingBodyweightSheet = false
    /// The workout awaiting the readiness check before its session begins.
    @State private var pendingWorkout: Workout?
    /// The day the hero card is showing. Nil = follow today, so the screen re-anchors
    /// itself when the app is left open past midnight.
    @State private var browsedDay: Weekday?
    /// Which calendar day the Today coach card was dismissed on (max one card per day).
    @AppStorage("coachCardDismissedDay") private var coachCardDismissedDay = ""

    init() {
        #if DEBUG
        if DebugSeed.wantsBodyweightSheet { _showingBodyweightSheet = State(initialValue: true) }
        #endif
    }

    private var profile: UserProfile { profiles.first ?? context.userProfile() }

    private var units: Units { settingsRows.first?.units ?? .kg }

    private var bodyweightSnapshot: BodyweightSnapshot? {
        BodyweightTracker.snapshot(entries: bodyweightEntries)
    }

    private var settings: AppSettings { settingsRows.first ?? context.appSettings() }

    /// A stable per-day key so the coach card can be dismissed for the rest of the day.
    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The single top-priority coach insight for the Today card, unless dismissed today.
    private var coachInsight: CoachInsight? {
        guard coachCardDismissedDay != todayKey else { return nil }
        let ctx = CoachContextBuilder.todayContext(
            profile: profile, settings: settings, plans: plans, context: context, catalog: catalog)
        return CoachEngine.topInsight(ctx)
    }

    /// A paused/in-progress session, if any (one at a time).
    private var activeSession: ActiveSession? { activeSessions.first }

    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }

    /// All workouts across all plans.
    private var allWorkouts: [Workout] {
        plans.flatMap(\.orderedWorkouts)
    }

    private var today: Weekday { Weekday.from(Date()) }

    /// The day the hero card is showing — today unless the user browsed elsewhere.
    private var shownDay: Weekday { browsedDay ?? today }

    private var isShowingToday: Bool { shownDay == today }

    /// The workout scheduled for the shown weekday (if any).
    private var shownWorkout: Workout? {
        allWorkouts.first { $0.day == shownDay }
    }

    private var otherWorkouts: [Workout] {
        allWorkouts.filter { $0.id != shownWorkout?.id }
    }

    private var streak: Int {
        StreakEngine.workoutStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates)
    }

    private var weekStreak: Int {
        StreakEngine.weekStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    WeekStripView(cells: StreakCalendar.weekStrip(doneDates: profile.doneDates),
                                  scheduled: scheduledDays,
                                  selected: shownDay) { select($0) }

                    if let insight = coachInsight {
                        CoachCardView(insight: insight) { coachCardDismissedDay = todayKey }
                            .onAppear {
                                if CoachContextBuilder.recordDailyCard(insight, context: context) != nil {
                                    try? context.save()
                                }
                            }
                    }

                    if let session = activeSession {
                        resumeBanner(session)
                    }

                    heroSectionHeader
                    Group {
                        if let workout = shownWorkout {
                            TodayHeroCard(workout: workout, catalog: catalog,
                                          isResuming: isActive(workout)) { start(workout) }
                        } else {
                            restDayCard
                        }
                    }
                    .id(shownDay)
                    // Opacity + a touch of scale rather than a slide: a `.move` transition
                    // overflows the enclosing ScrollView horizontally mid-animation.
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .gesture(heroSwipe)

                    if !otherWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Add Another Workout")
                            Text("Train extra today — won't change your schedule")
                                .font(.rounded(13, .semibold))
                                .foregroundStyle(Color.text3)
                        }
                        addAnotherScroller
                    }

                    quickStats

                    SectionHeader(title: "Bodyweight")
                    BodyweightCard(
                        snapshot: bodyweightSnapshot,
                        due: BodyweightTracker.checkInDue(lastDate: bodyweightSnapshot?.date),
                        units: units, goal: profile.goal
                    ) { showingBodyweightSheet = true }

                    if let highlight = recentHighlight { highlight }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .planNavigationDestinations()
            .sheet(item: $pendingWorkout) { workout in
                ReadinessCheckInSheet { readiness in
                    beginSession(workout, readiness: readiness)
                }
            }
            .sheet(isPresented: $showingBodyweightSheet) {
                BodyweightCheckInSheet(
                    initialKg: bodyweightSnapshot?.currentKg ?? 75,
                    units: units,
                    lastCheckInLine: bodyweightSnapshot.map {
                        "Last check-in: \(Formulas.formatBodyweight(kg: $0.currentKg, units: units)) · \($0.date.formatted(.relative(presentation: .named)))"
                    }
                ) { kg in
                    context.logBodyweight(kg)
                    try? context.save()
                }
            }
            .sheet(item: $selectedStat) { kind in
                StatDetailSheet(kind: kind, doneDates: profile.doneDates, history: history,
                                catalog: catalog, scheduledCount: scheduledDays.count,
                                workoutStreakValue: streak, weekStreakValue: weekStreak,
                                totalWorkouts: profile.totalWorkouts)
            }
        }
    }

    // MARK: Hero section header

    /// "Today's Workout" while anchored to today, otherwise the browsed day's name with
    /// a one-tap way back — the strip's today ring alone is easy to miss mid-scroll.
    private var heroSectionHeader: some View {
        HStack {
            SectionHeader(title: isShowingToday
                          ? (shownWorkout == nil ? "Today" : "Today's Workout")
                          : "\(shownDay.displayName)\(shownWorkout == nil ? "" : "'s Workout")")
            if !isShowingToday {
                Button { select(today) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .black))
                        Text("Today").font(.rounded(12, .heavy))
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentSoft))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func select(_ day: Weekday) {
        withAnimation(.snappy) { browsedDay = day == today ? nil : day }
    }

    /// Swipe the hero left/right to walk the week's workouts. A horizontal-only
    /// `DragGesture` with a real distance threshold, so it never competes with the
    /// enclosing vertical `ScrollView` — the card's Start button keeps its own taps
    /// because a drag and a tap are different gestures.
    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let day = value.translation.width < 0
                    ? WeekBrowser.next(after: shownDay, scheduled: scheduledDays)
                    : WeekBrowser.previous(before: shownDay, scheduled: scheduledDays)
                if let day { select(day) }
            }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).eyebrow()
                Text(profile.name).font(.screenTitle).foregroundStyle(Color.textPrimary)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accent)
                Text("\(streak)").font(.rounded(16, .black)).foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.surface))
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Add another

    private var addAnotherScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(otherWorkouts) { workout in
                    OtherWorkoutCard(workout: workout, isResuming: isActive(workout)) { start(workout) }
                }
                NewWorkoutCard { createPlanAndOpen() }
            }
        }
    }

    private func createPlanAndOpen() {
        let plan = PlanFactory.emptyPlan(into: context, order: Reordering.nextOrder(after: plans))
        try? context.save()
        path.append(plan)
    }

    // MARK: Stats

    private var thisWeekCount: Int {
        profile.doneDates.filter { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(weekStreak)", label: "Week streak") { selectedStat = .weekStreak }
            StatCard(value: "\(thisWeekCount)", label: "This week") { selectedStat = .thisWeek }
            StatCard(value: "\(profile.totalWorkouts)", label: "Workouts") { selectedStat = .workouts }
        }
    }

    @ViewBuilder
    private func resumeBanner(_ session: ActiveSession) -> some View {
        Button {
            session.isOpen = true
            try? context.save()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress").eyebrow()
                    Text(session.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Text("Continue").font(.rounded(14, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.accent))
            }
            .padding(14)
            .cardSurface(fill: Color.accentSoft)
        }
        .buttonStyle(.plain)
    }

    private func isActive(_ workout: Workout) -> Bool {
        activeSession?.workoutId == workout.id
    }

    private var recentHighlight: (some View)? {
        guard let best = history.max(by: { $0.e1rm < $1.e1rm }),
              let ex = catalog.exercise(id: best.exId) else { return Optional<AnyView>.none }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Recent Highlight")
                HStack(spacing: 12) {
                    ExerciseThumbnail(exercise: ex, size: 48, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                        Text("\(best.e1rm) est. 1RM").font(.rounded(13, .bold)).foregroundStyle(Color.accent)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill").foregroundStyle(Color.accent)
                }
                .padding(14)
                .cardSurface()
            }
        )
    }

    private var restDayCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 28)).foregroundStyle(Color.text3)
            Text("Rest day").font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text(isShowingToday
                 ? "No workout scheduled for today. Start an extra from below or your Plans."
                 : "Nothing scheduled for \(shownDay.displayName). Swipe or tap a day to keep looking.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardSurface()
    }

    // MARK: Actions

    private func start(_ workout: Workout) {
        // One session at a time: resume the in-progress one rather than starting a second.
        if let existing = activeSession {
            existing.isOpen = true
            try? context.save()
        } else {
            // A brand-new session first offers the optional readiness check.
            pendingWorkout = workout
        }
    }

    /// Begins a new session after the readiness sheet, applying any check-in.
    private func beginSession(_ workout: Workout, readiness: ReadinessCheckIn?) {
        if let readiness { context.logReadiness(readiness) }
        SessionBuilder.start(workout: workout, into: context, readiness: readiness)
        try? context.save()
    }
}

// MARK: - Hero card

private struct TodayHeroCard: View {
    let workout: Workout
    let catalog: ExerciseCatalog
    var isResuming: Bool = false
    let onStart: () -> Void

    private var muscleChips: [String] {
        var seen = Set<Muscle>()
        var result: [String] = []
        for item in workout.orderedItems {
            for muscle in catalog.exercise(id: item.exId)?.primaryMuscles ?? [] where seen.insert(muscle).inserted {
                result.append(muscle.displayName)
                if result.count == 3 { return result }
            }
        }
        return result
    }

    private var minutesEstimate: Int { max(20, workout.setCount * 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(workout.plan?.name ?? "") · \(workout.day.tag)")
                .font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.9))
            Text(workout.name).font(.rounded(28, .black)).foregroundStyle(.white)

            HStack(spacing: 24) {
                heroStat("\(workout.items.count)", "exercises")
                heroStat("\(minutesEstimate)", "min est.")
                heroStat("\(workout.setCount)", "sets")
            }

            HStack(spacing: 8) {
                ForEach(muscleChips, id: \.self) { chip in
                    Text(chip)
                        .font(.rounded(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }

            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: isResuming ? "arrow.forward.circle.fill" : "play.fill")
                    Text(isResuming ? "Continue" : "Start Workout")
                }
                .font(.rounded(16, .heavy)).foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous)
                .fill(LinearGradient(colors: [Color.accent, Color.accentPress],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: Color.accent.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.rounded(22, .black)).foregroundStyle(.white)
            Text(label).font(.rounded(11, .bold)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Other-workout & new cards

/// Tapping the card body opens the workout's detail (editor); the Start button is an
/// independent tap target overlaid at the bottom.
private struct OtherWorkoutCard: View {
    let workout: Workout
    var isResuming: Bool = false
    let onStart: () -> Void

    var body: some View {
        NavigationLink(value: workout) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: workout.plan?.colorHex ?? "#FF6A3D")).frame(width: 7, height: 7)
                    Text(workout.day.short).font(.rounded(11, .heavy)).foregroundStyle(Color.text3)
                }
                Text(workout.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
                Text(workout.plan?.name ?? "").font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    .lineLimit(1)
                Spacer(minLength: 4)
                startLabel.hidden()   // reserves layout space for the overlaid button
            }
            .padding(14)
            .frame(width: 150, height: 130, alignment: .topLeading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            Button(action: onStart) { startLabel }
                .buttonStyle(.plain)
                .padding(14)
        }
    }

    private var startLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: isResuming ? "arrow.forward.circle.fill" : "play.fill")
                .font(.system(size: 10, weight: .black))
            Text(isResuming ? "Continue" : "Start now").font(.rounded(13, .heavy))
        }
        .foregroundStyle(Color.accent)
    }
}

private struct NewWorkoutCard: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .black)).foregroundStyle(Color.accent)
                Text("New workout").font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
            }
            .frame(width: 150, height: 130)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(Color.border)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value).font(.metric).foregroundStyle(Color.textPrimary).tabularNumbers()
                Text(label).font(.rounded(12, .bold)).foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}
