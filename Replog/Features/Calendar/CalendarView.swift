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
    /// True when pushed inside another tab's NavigationStack (the Progress dashboard's
    /// Calendar card) — a pushed view must not nest a second stack, and it keeps the
    /// navigation bar for its Back button.
    var embedded: Bool = false

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
    /// Read-only: the singletons are bootstrapped in `ReplogApp.init`, so a view body
    /// never needs to create one — and must not, mid-render.
    private var doneDates: [Date] { profiles.first?.doneDates ?? [] }
    /// Credits bodyweight movements at their share of the athlete's weight.
    private var load: LoadResolver { .live(catalog: catalog, bodyweightEntries: bodyweightEntries) }
    private var units: Units { settingsRows.first?.units ?? .kg }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var scheduledDays: Set<Weekday> { StreakEngine.scheduledDays(in: plans) }

    // Recomputed only when the data changes (see refreshCaches) — a drag re-evaluates
    // the body on every crossed cell, and re-deriving these over all history per tick
    // (each entry JSON-decoding its sets) is where scrolling jank would come from.
    @State private var doneDays: Set<Date> = []
    @State private var dayTotals: [Date: DayTotals] = [:]

    private func refreshCaches() {
        doneDays = CalendarStats.doneDays(doneDates: doneDates,
                                          history: history, calendar: cal)
        dayTotals = CalendarStats.dayTotals(history: history, load: load, calendar: cal)
    }

    // Live-computed like Today/Profile — the stored profile.streak only refreshes on
    // finish/launch, so it can lag a missed day and contradict the other tabs.
    private var streak: Int {
        StreakEngine.workoutStreak(scheduledDays: scheduledDays, doneDates: doneDates)
    }
    private var weekStreak: Int {
        StreakEngine.weekStreak(scheduledDays: scheduledDays, doneDates: doneDates)
    }

    /// Months the pager can reach: three years back, one year forward.
    private var months: [Date] {
        (-36...12).compactMap { CalendarMath.month($0, from: Date(), calendar: cal) }
    }

    var body: some View {
        Group {
            if embedded {
                content.navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    content.toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        // `initial: true` rather than onAppear: the caches are @State, and onAppear can
        // run before @Query has delivered its first results — leaving an empty grid that
        // only a *subsequent* change would repair, which never comes. This form seeds on
        // the first evaluation that has data and refreshes on every change after.
        .onChange(of: history.count, initial: true) { refreshCaches() }
        .onChange(of: doneDates.count, initial: true) { refreshCaches() }
        .sensoryFeedback(.impact(weight: .medium), trigger: armTicks)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var content: some View {
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
                streakChip(icon: "flame.fill", value: "\(streak)")
                streakChip(icon: "calendar.badge.checkmark", value: "\(weekStreak)w")
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
        HStack(spacing: 8) {
            Text((visibleMonth ?? today).formatted(.dateTime.month(.wide).year()))
                .font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            // Only shown when the pager has wandered off the current month, so there is
            // always one tap back to today rather than an unknown number of swipes.
            if let visible = visibleMonth, !cal.isDate(visible, equalTo: today, toGranularity: .month) {
                Button {
                    withAnimation(.snappy) { visibleMonth = CalendarMath.month(0, from: Date(), calendar: cal) }
                } label: {
                    Text("Today").font(.rounded(12, .heavy)).foregroundStyle(Color.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentSoft))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
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
        let totals = CalendarStats.monthTotals(month: month, doneDays: doneDays,
                                               dayTotals: dayTotals, calendar: cal)
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
                                               doneDates: doneDates,
                                               history: history, load: load, calendar: cal),
                units: units, catalog: catalog,
                onClear: { withAnimation(.snappy) { selection = [] } }
            )
        } else {
            DayDetailView(
                day: focusedDay,
                isDone: doneDays.contains(focusedDay),
                entries: CalendarStats.entries(on: focusedDay, history: history, load: load, calendar: cal),
                bodyweight: bodyweight(on: focusedDay),
                units: units, catalog: catalog, load: load
            )
        }
    }

    private func bodyweight(on day: Date) -> Double? {
        bodyweightEntries.last { cal.isDate($0.date, inSameDayAs: day) }?.weightKg
    }
}
