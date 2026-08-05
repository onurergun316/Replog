//
//  ProfileView.swift
//  Replog
//
//  Avatar + goal, lifetime stats, and preferences (units, dark mode, rest timer),
//  plus a reset.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var profiles: [UserProfile]
    @Query private var settingsList: [AppSettings]
    @Query private var plans: [Plan]
    @Query private var history: [HistoryEntry]
    @Query(sort: \BadgeAward.earnedAt, order: .reverse) private var awards: [BadgeAward]
    @State private var showResetConfirm = false
    @State private var selectedStat: StatKind?
    /// Built once when the screen appears — walking the whole history is not view-body work.
    @State private var badgeSnapshot = BadgeSnapshot()

    private var profile: UserProfile { profiles.first ?? context.userProfile() }
    private var settings: AppSettings { settingsList.first ?? context.appSettings() }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }
    private var plansWithReports: [Plan] { plans.filter(\.hasReport) }
    /// Surfaced coach insights (debriefs, milestones, Today cards), newest first. The list
    /// scrolls inside a fixed height and groups itself, so it can hold a real history rather
    /// than the handful a flat list could show without stretching the screen.
    private var recentInsights: [CoachingLog] { context.coachingLogs(kind: .coachInsight, limit: 200) }
    /// Published weekly + monthly narrative reports, newest first.
    private var trainingReports: [CoachingLog] {
        (context.coachingLogs(kind: .weeklyReport) + context.coachingLogs(kind: .monthlyReport))
            .sorted { $0.date > $1.date }
    }
    @State private var reportToRead: CoachingLog?
    private var workoutStreak: Int {
        StreakEngine.workoutStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates)
    }
    private var weekStreak: Int {
        StreakEngine.weekStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Profile").font(.screenTitle).foregroundStyle(Color.textPrimary)
                    profileHeader
                    statsRow
                    SubscriptionSection()
                    badgesSection
                    if !plansWithReports.isEmpty { coachReports }
                    if !trainingReports.isEmpty { trainingReportsSection }
                    if !recentInsights.isEmpty { coachInsightsSection }
                    preferences
                    notificationsSection
                    LegalSection()
                    resetButton
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.immediately)
            .hideKeyboardOnTap()
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                badgeSnapshot = BadgeAwarding.snapshot(context: context, catalog: catalog)
            }
            .confirmationDialog("Reset all data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all plans, history, and settings, and restarts onboarding.")
            }
            .sheet(item: $selectedStat) { kind in
                StatDetailSheet(kind: kind, doneDates: profile.doneDates, history: history,
                                catalog: catalog, scheduledCount: scheduledDays.count,
                                workoutStreakValue: workoutStreak, weekStreakValue: weekStreak,
                                totalWorkouts: profile.totalWorkouts)
            }
            .sheet(item: $reportToRead) { report in
                NavigationStack {
                    CoachReportView(title: report.summary, markdown: report.bodyMarkdown ?? "",
                                    showsDoneButton: true)
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Text(profile.initial)
                .font(.rounded(24, .black)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(LinearGradient(colors: [Color.accent, Color.accentPress],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).font(.rounded(20, .black)).foregroundStyle(Color.textPrimary)
                Text(profile.goal.displayName).font(.rounded(13, .bold)).foregroundStyle(Color.accent)
            }
            Spacer()
        }
        .padding(16)
        .cardSurface()
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("\(profile.totalWorkouts)", "Workouts") { selectedStat = .workouts }
            stat("\(workoutStreak)", "Workout streak") { selectedStat = .workoutStreak }
            stat("\(weekStreak)", "Week streak") { selectedStat = .weekStreak }
        }
    }

    private var trainingReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Training Reports")
            ForEach(trainingReports) { report in
                Button { reportToRead = report } label: {
                    HStack(spacing: 12) {
                        Image(systemName: report.kind == .monthlyReport ? "calendar" : "calendar.day.timeline.left")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                            .frame(width: 24)
                        Text(report.summary)
                            .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14).cardSurface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coachInsightsSection: some View {
        CoachInsightsListView(logs: recentInsights)
    }

    /// The trophy cabinet. Built lazily on appear rather than on every render: the snapshot
    /// walks the whole history, which is not something to do inside a view body.
    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Badges")
            NavigationLink { BadgesView() } label: {
                BadgeSummaryCard(awards: awards, snapshot: badgeSnapshot)
            }
            .buttonStyle(.plain)
        }
    }

    private var coachReports: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AI Coach Reports")
            VStack(spacing: 0) {
                ForEach(Array(plansWithReports.enumerated()), id: \.element.id) { index, plan in
                    NavigationLink {
                        CoachReportView(title: plan.headline.isEmpty ? plan.name : plan.headline,
                                        markdown: plan.reportMarkdown)
                    } label: {
                        HStack(spacing: 12) {
                            icon("sparkles")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                                Text("The science behind your plan")
                                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.text3)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    if index < plansWithReports.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .cardSurface()
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Notifications")
            VStack(spacing: 0) {
                toggleRow(icon: "bell.fill", title: "Enable notifications",
                          isOn: Binding(get: { settings.notificationsEnabled },
                                        set: { setNotificationsEnabled($0) }))
                if settings.notificationsEnabled {
                    Divider().padding(.leading, 14)
                    reminderTimeRow
                    Divider().padding(.leading, 14)
                    notifyToggle("figure.run", "Workout reminders",
                                 Binding(get: { settings.notifyWorkoutReminder },
                                         set: { settings.notifyWorkoutReminder = $0; saveAndRefresh() }))
                    Divider().padding(.leading, 14)
                    notifyToggle("flame.fill", "Streak reminders",
                                 Binding(get: { settings.notifyStreakRisk },
                                         set: { settings.notifyStreakRisk = $0; saveAndRefresh() }))
                    Divider().padding(.leading, 14)
                    notifyToggle("doc.text.fill", "Report ready",
                                 Binding(get: { settings.notifyReportReady },
                                         set: { settings.notifyReportReady = $0; saveAndRefresh() }))
                    Divider().padding(.leading, 14)
                    notifyToggle("scalemass.fill", "Check-in reminders",
                                 Binding(get: { settings.notifyCheckInDue },
                                         set: { settings.notifyCheckInDue = $0; saveAndRefresh() }))
                }
            }
            .cardSurface()
            Text("Encouraging nudges only — at most one a day, never during quiet hours (9pm–9am).")
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                .padding(.horizontal, 4)
        }
    }

    private func notifyToggle(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        toggleRow(icon: icon, title: title, isOn: binding)
    }

    private var reminderTimeRow: some View {
        HStack(spacing: 12) {
            icon("clock.fill")
            Text("Reminder time").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
            Spacer()
            Stepper(reminderTimeLabel, value: Binding(
                get: { settings.reminderHour },
                set: { settings.reminderHour = min(23, max(0, $0)); saveAndRefresh() }),
                in: 0...23)
                .labelsHidden()
            Text(reminderTimeLabel).font(.rounded(14, .heavy)).foregroundStyle(Color.text2)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(14)
    }

    private var reminderTimeLabel: String {
        let h = settings.reminderHour
        let period = h < 12 ? "AM" : "PM"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12):00 \(period)"
    }

    private func setNotificationsEnabled(_ on: Bool) {
        if on {
            Task {
                let granted = await NotificationScheduler.requestAuthorization()
                settings.notificationsEnabled = granted
                saveAndRefresh()
            }
        } else {
            settings.notificationsEnabled = false
            saveAndRefresh()
        }
    }

    private func saveAndRefresh() {
        save()
        NotificationCoordinator.refresh(context: context)
    }

    private func stat(_ value: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value).font(.metric).foregroundStyle(Color.textPrimary).tabularNumbers()
                Text(label).font(.rounded(12, .bold)).foregroundStyle(Color.text2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Preferences")
            VStack(spacing: 0) {
                restDurationRow
                Divider().padding(.leading, 14)
                toggleRow(icon: "timer", title: "Rest timer auto-start",
                          isOn: Binding(get: { settings.restTimerAuto },
                                        set: { settings.restTimerAuto = $0; save() }))
                Divider().padding(.leading, 14)
                unitsRow
                Divider().padding(.leading, 14)
                toggleRow(icon: "moon.fill", title: "Dark mode",
                          isOn: Binding(get: { settings.darkMode },
                                        set: { settings.darkMode = $0; save() }))
            }
            .cardSurface()
        }
    }

    /// The app-wide default rest between sets (per-exercise overrides win in a workout).
    private var restDurationRow: some View {
        HStack(spacing: 12) {
            icon("clock.arrow.circlepath")
            Text("Rest duration").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
            Spacer()
            NumericStepperField(display: "\(settings.restSeconds)", keyboard: .numberPad,
                                onMinus: { settings.restSeconds = max(5, settings.restSeconds - 15); save() },
                                onPlus: { settings.restSeconds = min(600, settings.restSeconds + 15); save() },
                                onCommit: {
                                    if let v = Int($0.filter(\.isNumber)) {
                                        settings.restSeconds = min(600, max(5, v)); save()
                                    }
                                })
            Text("sec").font(.rounded(11, .bold)).foregroundStyle(Color.text3)
        }
        .padding(14)
    }

    private var unitsRow: some View {
        HStack(spacing: 12) {
            icon("scalemass.fill")
            Text("Units").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
            Spacer()
            SegmentedToggle(options: [(Units.kg, "kg"), (Units.lb, "lb")],
                            selection: Binding(get: { settings.units },
                                               set: { settings.units = $0; save() }))
                .frame(width: 120)
        }
        .padding(14)
    }

    private func toggleRow(icon iconName: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            icon(iconName)
            Text(title).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(.accent)
        }
        .padding(14)
    }

    private func icon(_ name: String) -> some View { SettingsRowIcon(systemName: name) }

    private var resetButton: some View {
        Button(role: .destructive) { showResetConfirm = true } label: {
            HStack(spacing: 6) { Image(systemName: "arrow.counterclockwise"); Text("Reset all data") }
                .font(.rounded(15, .heavy)).foregroundStyle(Color.down)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.down.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func save() { try? context.save() }

    /// Wipes the athlete's training data and sends them back through onboarding.
    ///
    /// Deliberately does NOT touch `AppSettings` — and in particular not
    /// `AppSettings.freeDayDate`. Resetting your data is a reasonable thing to want; being
    /// handed a fresh free day every time you did it would make Premium optional.
    private func resetAll() {
        for plan in plans { context.delete(plan) }
        for entry in history { context.delete(entry) }
        let sessions = (try? context.fetch(FetchDescriptor<ActiveSession>())) ?? []
        for session in sessions { context.delete(session) }
        profile.onboardingDone = false
        profile.name = ""
        profile.streak = 0
        profile.weekStreak = 0
        profile.totalWorkouts = 0
        profile.doneDates = []
        try? context.save()
    }
}
