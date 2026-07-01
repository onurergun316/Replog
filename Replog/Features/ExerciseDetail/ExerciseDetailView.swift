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
    let exId: String
    var showProgress: Bool = false

    @State private var tab: DetailTab = .guide

    enum DetailTab: Hashable { case guide, progress }

    private var exercise: Exercise? { catalog.exercise(id: exId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let exercise {
                    PhotoCarousel(resourceNames: exercise.imageResourceNames)
                    Text(exercise.name).font(.rounded(24, .black)).foregroundStyle(Color.textPrimary)

                    if showProgress {
                        SegmentedToggle(options: [(DetailTab.guide, "Guide"), (.progress, "Progress")],
                                        selection: $tab)
                    }

                    if tab == .guide || !showProgress {
                        GuideContent(exercise: exercise)
                    } else {
                        ProgressContent(exId: exId, history: context.history(forExercise: exId))
                    }
                } else {
                    Text("Exercise not found").foregroundStyle(Color.text2)
                }
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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
    let exId: String
    let history: [HistoryEntry]

    private var progress: ExerciseProgress {
        ProgressAggregator.summarize(exId: exId, history: history)
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

    private var chart: some View {
        Chart(Array(history.sorted { $0.date < $1.date }.enumerated()), id: \.offset) { index, entry in
            LineMark(x: .value("Session", index), y: .value("1RM", entry.e1rm))
                .foregroundStyle(Color.accent)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("Session", index), y: .value("1RM", entry.e1rm))
                .foregroundStyle(LinearGradient(colors: [Color.accent.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis(.hidden)
        .frame(height: 180)
        .padding(14)
        .cardSurface()
    }

    private var sessionLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Session Log")
            ForEach(history.sorted { $0.date > $1.date }) { entry in
                HStack(alignment: .top) {
                    Text(entry.date, format: .dateTime.month().day())
                        .font(.rounded(13, .heavy)).foregroundStyle(Color.text2).frame(width: 60, alignment: .leading)
                    Text(entry.sets.map { "\(Int($0.w))kg × \($0.r)" }.joined(separator: " · "))
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}
