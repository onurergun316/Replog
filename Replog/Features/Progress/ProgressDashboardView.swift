//
//  ProgressDashboardView.swift
//  Replog
//
//  Pick a plan, then see its exercises grouped under each workout, each with current
//  est-1RM, trend %, and a sparkline. Tap to open the exercise's Progress detail.
//

import SwiftUI
import SwiftData

struct ProgressDashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query private var allHistory: [HistoryEntry]
    @State private var selectedPlanID: UUID?

    /// True when pushed inside another tab's NavigationStack (Profile's "Progress &
    /// Trends" card) rather than standing alone — a pushed view must not nest a second
    /// stack, and it keeps the navigation bar for its Back button.
    var embedded: Bool = false

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID } ?? plans.first
    }

    private func historyByExercise(_ exId: String) -> [HistoryEntry] {
        allHistory.filter { $0.exId == exId }
    }

    var body: some View {
        if embedded {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            NavigationStack {
                content.toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Progress").font(.screenTitle).foregroundStyle(Color.textPrimary)

                if plans.isEmpty {
                    emptyState
                } else {
                    planPills
                    if let plan = selectedPlan {
                        ForEach(plan.orderedWorkouts) { workout in
                            workoutSection(workout)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationDestination(for: ExerciseRef.self) { ref in
            ExerciseDetailView(exId: ref.id, showProgress: true)
        }
    }

    private var planPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plans) { plan in
                    let isSelected = plan.id == (selectedPlan?.id)
                    Button { selectedPlanID = plan.id } label: {
                        Text(plan.name)
                            .font(.rounded(13, .heavy))
                            .foregroundStyle(isSelected ? .white : Color.text2)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workoutSection(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Pill(text: workout.slotLabel, style: .accentSoft)
                Text(workout.name).font(.cardTitle).foregroundStyle(Color.textPrimary)
            }
            ForEach(workout.orderedItems) { item in
                NavigationLink(value: ExerciseRef(id: item.exId)) {
                    ProgressRow(
                        name: catalog.exercise(id: item.exId)?.name ?? item.exId,
                        progress: ProgressAggregator.summarize(exId: item.exId, history: historyByExercise(item.exId))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 28)).foregroundStyle(Color.text3)
            Text("No plans yet").font(.cardTitle).foregroundStyle(Color.textPrimary)
            Text("Create a plan and log workouts to track your progression.")
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }
}

// MARK: - Row

private struct ProgressRow: View {
    let name: String
    let progress: ExerciseProgress

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(progress.hasData ? "\(progress.currentE1rm) 1RM" : "No data")
                        .font(.rounded(12, .bold)).foregroundStyle(Color.text2)
                    if let pct = progress.trendPercent {
                        HStack(spacing: 2) {
                            Image(systemName: progress.trend.symbol).font(.system(size: 8, weight: .black))
                            Text("\(abs(Int(pct.rounded())))%").font(.rounded(11, .heavy))
                        }
                        .foregroundStyle(progress.trend.color)
                    }
                }
            }
            Spacer()
            Sparkline(values: progress.series)
                .frame(width: 64, height: 30)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.text3)
        }
        .padding(14)
        .cardSurface()
    }
}
