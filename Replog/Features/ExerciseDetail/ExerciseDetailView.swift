//
//  ExerciseDetailView.swift
//  Replog
//
//  Industry-standard movement page. Opened from the Library it's Guide-only;
//  from Progress or a workout it gains a Guide | Progress toggle with a chart and
//  the session log.
//

import SwiftUI
import SwiftData
import Charts

struct ExerciseDetailView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    let exId: String
    var showProgress: Bool = false

    @State private var tab: DetailTab = .progress
    @State private var showAddToWorkout = false

    enum DetailTab: Hashable { case guide, progress }

    private var exercise: Exercise? { catalog.exercise(id: exId) }
    private var membership: [PlanWorkouts] { WorkoutMembership.grouped(containing: exId, in: plans) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let exercise {
                    PhotoCarousel(resourceNames: exercise.imageResourceNames)
                    Text(exercise.name).font(.rounded(24, .black)).foregroundStyle(Color.textPrimary)

                    if showProgress {
                        SegmentedToggle(options: [(DetailTab.progress, "Progress"), (.guide, "Guide")],
                                        selection: $tab)
                    }

                    if tab == .guide || !showProgress {
                        GuideContent(exercise: exercise)
                        addToWorkoutSection
                    } else {
                        ProgressContent(exId: exId, history: context.history(forExercise: exId),
                                        load: .live(catalog: catalog,
                                                    bodyweightEntries: bodyweightEntries))
                    }
                } else {
                    Text("Exercise not found").foregroundStyle(Color.text2)
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddToWorkout) {
            AddToWorkoutSheet(exIds: [exId])
        }
    }

    /// "In your workouts" chips + an Add button. Hidden when the user has no plans yet
    /// (e.g. the read-only preview during onboarding).
    @ViewBuilder
    private var addToWorkoutSection: some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !membership.isEmpty {
                    SectionHeader(title: "In Your Workouts")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(membership) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.plan.name)
                                    .font(.rounded(11, .heavy)).textCase(.uppercase).tracking(0.8)
                                    .foregroundStyle(Color.text3).lineLimit(1)
                                FlowLayout(spacing: 8) {
                                    ForEach(group.workouts) { workout in
                                        Pill(text: workout.name, style: .accentSoft)
                                    }
                                }
                            }
                        }
                    }
                }
                Button { showAddToWorkout = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(membership.isEmpty ? "Add to workout" : "Add to another workout")
                    }
                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Photo carousel

private struct PhotoCarousel: View {
    let resourceNames: [String]
    @State private var index = 0

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(resourceNames.enumerated()), id: \.offset) { i, name in
                ZoomablePhoto(resourceName: name).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: resourceNames.count > 1 ? .always : .never))
        .frame(height: 320)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface2))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// A single photo shown in full (aspect-fit, never cropped) with pinch- and
/// double-tap-to-zoom for close inspection of the movement.
private struct ZoomablePhoto: View {
    let resourceName: String
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ExerciseImageView(resourceName: resourceName, cornerRadius: Radius.card, contentMode: .fit)
            .scaleEffect(scale * pinch)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(1, scale * value.magnification), 4) }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { scale = scale > 1 ? 1 : 2 }
            }
    }
}

// MARK: - Guide

private struct GuideContent: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            tagGrid
            musclesWorked
            if !exercise.instructions.isEmpty { instructions }
        }
    }

    private var tagGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tag("Equipment", exercise.equipment?.displayName ?? "Bodyweight")
            tag("Level", exercise.level.displayName)
            tag("Force", exercise.force?.displayName ?? "—")
            tag("Type", exercise.category.displayName)
        }
    }

    private func tag(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.rounded(11, .heavy)).textCase(.uppercase).tracking(1)
                .foregroundStyle(Color.text3)
            Text(value).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardSurface(radius: Radius.chip)
    }

    private var musclesWorked: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Muscles Worked")
                Spacer()
                HStack(spacing: 10) {
                    legend(color: .accent, text: "Primary")
                    legend(color: .accentSoft, text: "Secondary")
                }
            }
            FlowChips(
                primary: exercise.primaryMuscles.map(\.displayName),
                secondary: exercise.secondaryMuscles.map(\.displayName)
            )
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.rounded(11, .bold)).foregroundStyle(Color.text3)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Instructions")
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.rounded(13, .black)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accent))
                    Text(step).font(.bodyText).foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Wraps primary (accent) and secondary (soft) muscle pills.
private struct FlowChips: View {
    let primary: [String]
    let secondary: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(primary, id: \.self) { Pill(text: $0, style: .accent) }
            ForEach(secondary, id: \.self) { Pill(text: $0, style: .accentSoft) }
        }
    }
}

// MARK: - Progress

private struct ProgressContent: View {
    @State private var expandedEntryID: UUID?
    let exId: String
    let history: [HistoryEntry]
    let load: LoadResolver

    private var progress: ExerciseProgress {
        ProgressAggregator.summarize(exId: exId, history: history, load: load)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if progress.hasData {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(progress.bestE1rm)").font(.bigMetric).foregroundStyle(Color.textPrimary).tabularNumbers()
                    Text("best est. 1RM").font(.rounded(13, .bold)).foregroundStyle(Color.text2)
                }
                chart
                sessionLog
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 26)).foregroundStyle(Color.text3)
                    Text("No history yet").font(.cardTitle).foregroundStyle(Color.textPrimary)
                    Text("Log this exercise in a workout to see your progression.")
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }

    private var sorted: [HistoryEntry] { history.sorted { $0.date < $1.date } }

    /// One session is a picture of a session, not a trend: a single point plotted against
    /// a hidden ordinal axis was the "chart shows nothing" the athlete saw after two
    /// workouts. Below three sessions this renders that session's sets instead.
    @ViewBuilder
    private var chart: some View {
        if sorted.count < 2, let latest = sorted.last {
            setBreakdownChart(latest)
        } else {
            trendChart
        }
    }

    /// Estimated 1RM over real dates — two sessions three days apart no longer look
    /// identical to two sessions three months apart.
    private var trendChart: some View {
        Chart(sorted, id: \.id) { entry in
            LineMark(x: .value("Date", entry.date), y: .value("1RM", load.e1rm(entry)))
                .foregroundStyle(Color.accent)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Date", entry.date), y: .value("1RM", load.e1rm(entry)))
                .foregroundStyle(LinearGradient(colors: [Color.accent.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", entry.date), y: .value("1RM", load.e1rm(entry)))
                .foregroundStyle(Color.accent)
                .symbolSize(40)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis { AxisMarks(format: .dateTime.month(.abbreviated).day()) }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 180)
        .padding(14)
        .cardSurface()
    }

    /// The baseline view: every set of the only logged session, so the screen carries
    /// real information from the very first workout.
    private func setBreakdownChart(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                BarMark(x: .value("Set", "\(index + 1)"),
                        y: .value("Weight", set.w))
                    .foregroundStyle(Color.accent)
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        Text("\(set.r)").font(.rounded(10, .bold)).foregroundStyle(Color.text3)
                    }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
            Text("Your baseline — log this again to see a trend")
                .font(.rounded(11, .semibold)).foregroundStyle(Color.text3)
        }
        .padding(14)
        .cardSurface()
    }

    private var sessionLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Session Log")
            ForEach(history.sorted { $0.date > $1.date }) { entry in
                SessionLogRow(entry: entry, isExpanded: expandedEntryID == entry.id) {
                    withAnimation(.snappy) {
                        expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
                    }
                }
                Divider()
            }
        }
    }
}

/// One logged session, collapsed to its headline (deepest onion layer): date, top set,
/// set count. Tapping expands the set-by-set breakdown — detail on request, never dumped.
private struct SessionLogRow: View {
    let entry: HistoryEntry
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(entry.date, format: .dateTime.month().day())
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.text2)
                        .frame(width: 60, alignment: .leading)
                    Text("\(Int(entry.topW))kg × \(entry.topR) top set · \(entry.sets.count) set\(entry.sets.count == 1 ? "" : "s")")
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(entry.e1rm)").font(.rounded(13, .black))
                        .foregroundStyle(Color.accent).tabularNumbers()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.text3)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(.rounded(12, .bold)).foregroundStyle(Color.text3)
                                .frame(width: 60, alignment: .leading)
                            Text("\(Int(set.w)) kg × \(set.r)")
                                .font(.rounded(12, .semibold)).foregroundStyle(Color.textPrimary)
                                .tabularNumbers()
                            Spacer()
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}
