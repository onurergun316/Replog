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
    @Query private var profiles: [UserProfile]
    @Query private var settingsList: [AppSettings]
    @Query private var plans: [Plan]
    @Query private var history: [HistoryEntry]
    @State private var showResetConfirm = false

    private var profile: UserProfile { profiles.first ?? context.userProfile() }
    private var settings: AppSettings { settingsList.first ?? context.appSettings() }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }
    private var plansWithReports: [Plan] { plans.filter(\.hasReport) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Profile").font(.screenTitle).foregroundStyle(Color.textPrimary)
                    profileHeader
                    statsRow
                    if !plansWithReports.isEmpty { coachReports }
                    preferences
                    resetButton
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Reset all data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all plans, history, and settings, and restarts onboarding.")
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
            stat("\(profile.totalWorkouts)", "Workouts")
            stat("\(StreakEngine.workoutStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates))",
                 "Workout streak")
            stat("\(StreakEngine.weekStreak(scheduledDays: scheduledDays, doneDates: profile.doneDates))",
                 "Week streak")
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.metric).foregroundStyle(Color.textPrimary).tabularNumbers()
            Text(label).font(.rounded(12, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).cardSurface()
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Preferences")
            VStack(spacing: 0) {
                unitsRow
                Divider().padding(.leading, 14)
                toggleRow(icon: "moon.fill", title: "Dark mode",
                          isOn: Binding(get: { settings.darkMode },
                                        set: { settings.darkMode = $0; save() }))
                Divider().padding(.leading, 14)
                toggleRow(icon: "timer", title: "Rest timer auto-start",
                          isOn: Binding(get: { settings.restTimerAuto },
                                        set: { settings.restTimerAuto = $0; save() }))
            }
            .cardSurface()
        }
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

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.accent)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentSoft))
    }

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
