//
//  CalendarView.swift
//  Replog
//
//  The Calendar tab (see CALENDAR_DESIGN.md): streak header, horizontally-paged month
//  grid, and below it either one day's training detail or — after a long-press drag
//  across days — a range summary with totals and per-training-day averages. Days are
//  binary (any finished workout marks its day), matching the streak engine.
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.exerciseCatalog) private var catalog
    @Query private var profiles: [UserProfile]
    @Query private var history: [HistoryEntry]
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(sort: \BodyweightEntry.date) private var bodyweightEntries: [BodyweightEntry]
    @Query private var settingsRows: [AppSettings]

    private static let calendar = CalendarMath.gridCalendar()

    @State private var selection: Set<Date> = []
    @State private var visibleMonth: Date? = CalendarMath.month(0, from: Date(),
                                                               calendar: CalendarView.calendar)
    /// True while a long-press drag is picking days — pauses scrolling and paging.
    @State private var isSelecting = false
    /// Whether the in-flight drag is adding days (from the first cell's inverted state).
    @State private var dragAdds = true
    @State private var armTicks = 0

    private var cal: Calendar { Self.calendar }
    private var profile: UserProfile { profiles.first ?? context.userProfile() }
    private var units: Units { settingsRows.first?.units ?? .kg }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }
    private var doneDays: Set<Date> {
        CalendarStats.doneDays(doneDates: profile.doneDates, history: history, calendar: cal)
    }

    /// Months the pager can reach: three years back, one year forward.
    private var months: [Date] {
        (-36...12).compactMap { CalendarMath.month($0, from: Date(), calendar: cal) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    monthHeader
                    monthPager
                    detailSection
                }
                .padding(20)
            }
            .scrollDisabled(isSelecting)
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: armTicks)
        .sensoryFeedback(.selection, trigger: selection)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your training log").eyebrow()
                Text("Calendar").font(.screenTitle).foregroundStyle(Color.textPrimary)
            }
            Spacer()
            HStack(spacing: 6) {
                streakChip(icon: "flame.fill", value: "\(profile.streak)")
                streakChip(icon: "calendar.badge.checkmark", value: "\(profile.weekStreak)w")
            }
        }
    }

    private func streakChip(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accent)
            Text(value).font(.rounded(15, .black)).foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
    }

    // MARK: Month paging

    private var monthHeader: some View {
        HStack {
            Text((visibleMonth ?? today).formatted(.dateTime.month(.wide).year()))
                .font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            Spacer()
            monthChevron("chevron.left", step: -1)
            monthChevron("chevron.right", step: 1)
        }
    }

    private func monthChevron(_ symbol: String, step: Int) -> some View {
        Button {
            guard let current = visibleMonth,
                  let next = cal.date(byAdding: .month, value: step, to: current),
                  months.contains(next) else { return }
            withAnimation(.snappy) { visibleMonth = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.text2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.surface2))
        }
        .buttonStyle(.plain)
    }

    private var monthPager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    MonthGridView(
                        month: month, calendar: cal, doneDays: doneDays,
                        scheduled: scheduledDays, selection: selection,
                        footer: footerLine(for: month),
                        onTap: { tap($0) },
                        onDragBegan: { dragBegan($0) },
                        onDragMoved: { dragMoved($0) },
                        onDragEnded: { dragEnded() }
                    )
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleMonth)
        .scrollDisabled(isSelecting)
    }

    private func footerLine(for month: Date) -> String {
        let totals = CalendarStats.monthTotals(month: month, doneDates: profile.doneDates,
                                               history: history, calendar: cal)
        guard totals.workouts > 0 else { return "No workouts this month yet" }
        let volume = Formulas.formatWeight(kg: totals.volumeKg, units: units)
        return "\(totals.workouts) \(totals.workouts == 1 ? "workout" : "workouts") · \(volume) lifted"
    }

    // MARK: Selection

    private func tap(_ day: Date) {
        withAnimation(.snappy) {
            selection = selection == [day] ? [] : [day]
        }
    }

    private func dragBegan(_ day: Date) {
        isSelecting = true
        armTicks += 1
        dragAdds = !selection.contains(day)
        apply(day)
    }

    private func dragMoved(_ day: Date) { apply(day) }

    private func dragEnded() { isSelecting = false }

    private func apply(_ day: Date) {
        withAnimation(.snappy) {
            if dragAdds { selection.insert(day) } else { selection.remove(day) }
        }
    }

    // MARK: Detail

    /// The day whose detail shows when zero/one day is selected. No selection = today.
    private var focusedDay: Date { selection.first ?? today }

    @ViewBuilder
    private var detailSection: some View {
        if selection.count > 1 {
            RangeSummaryView(
                summary: CalendarStats.summary(selection: selection,
                                               doneDates: profile.doneDates,
                                               history: history, calendar: cal),
                units: units, catalog: catalog,
                onClear: { withAnimation(.snappy) { selection = [] } }
            )
        } else {
            DayDetailView(
                day: focusedDay,
                isDone: doneDays.contains(focusedDay),
                entries: CalendarStats.entries(on: focusedDay, history: history, calendar: cal),
                bodyweight: bodyweight(on: focusedDay),
                units: units, catalog: catalog
            )
        }
    }

    private func bodyweight(on day: Date) -> Double? {
        bodyweightEntries.last { cal.isDate($0.date, inSameDayAs: day) }?.weightKg
    }
}
