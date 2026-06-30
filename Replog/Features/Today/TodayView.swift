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

    @State private var path = NavigationPath()

    private var profile: UserProfile { profiles.first ?? context.userProfile() }

    /// All workouts across all plans.
    private var allWorkouts: [Workout] {
        plans.flatMap(\.orderedWorkouts)
    }

    /// The workout scheduled for today's weekday (if any).
    private var todaysWorkout: Workout? {
        let today = Weekday.from(Date())
        return allWorkouts.first { $0.day == today }
    }

    private var otherWorkouts: [Workout] {
        allWorkouts.filter { $0.id != todaysWorkout?.id }
    }

    private var streak: Int {
        StreakCalendar.streak(doneDates: profile.doneDates)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    WeekStripView(cells: StreakCalendar.weekStrip(doneDates: profile.doneDates))

                    if let workout = todaysWorkout {
                        SectionHeader(title: "Today's Workout")
                        TodayHeroCard(workout: workout, catalog: catalog) { start(workout) }
                    } else {
                        SectionHeader(title: "Today")
                        restDayCard
                    }

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
                    if let highlight = recentHighlight { highlight }
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .planNavigationDestinations()
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
                Text("🔥").font(.system(size: 16))
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
                    OtherWorkoutCard(workout: workout) { start(workout) }
                }
                NewWorkoutCard { createPlanAndOpen() }
            }
        }
    }

    private func createPlanAndOpen() {
        let plan = PlanFactory.emptyPlan(into: context, order: plans.count)
        try? context.save()
        path.append(plan)
    }

    // MARK: Stats

    private var quickStats: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(profile.doneDates.filter { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .weekOfYear) }.count)",
                     label: "This week")
            StatCard(value: "\(profile.totalWorkouts)", label: "Workouts")
        }
    }

    private var recentHighlight: (some View)? {
        guard let best = history.max(by: { $0.e1rm < $1.e1rm }),
              let ex = catalog.exercise(id: best.exId) else { return Optional<AnyView>.none }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Recent Highlight")
                HStack(spacing: 12) {
                    ExerciseImageView(exercise: ex, cornerRadius: 12)
                        .frame(width: 48, height: 48)
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
            Text("No workout scheduled for today. Start an extra from below or your Plans.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardSurface()
    }

    // MARK: Actions

    private func start(_ workout: Workout) {
        SessionBuilder.start(workout: workout, into: context)
        try? context.save()
    }
}

// MARK: - Hero card

private struct TodayHeroCard: View {
    let workout: Workout
    let catalog: ExerciseCatalog
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
                    Image(systemName: "play.fill")
                    Text("Start Workout")
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

private struct OtherWorkoutCard: View {
    let workout: Workout
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: workout.plan?.colorHex ?? "#FF6A3D")).frame(width: 7, height: 7)
                Text(workout.day.short).font(.rounded(11, .heavy)).foregroundStyle(Color.text3)
            }
            Text(workout.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text(workout.plan?.name ?? "").font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onStart) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .black))
                    Text("Start now").font(.rounded(13, .heavy))
                }
                .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 150, height: 130, alignment: .topLeading)
        .cardSurface()
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
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.metric).foregroundStyle(Color.textPrimary).tabularNumbers()
            Text(label).font(.rounded(12, .bold)).foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardSurface()
    }
}
