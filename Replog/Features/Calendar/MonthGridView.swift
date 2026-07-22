//
//  MonthGridView.swift
//  Replog
//
//  One month page of the Calendar tab: weekday header, a fixed 42-cell Sunday-first
//  grid (CalendarMath), and a month-totals footer. One encoding per cell: accent fill =
//  trained, ring = today, dot = scheduled future day, soft chip = selected. Taps select;
//  the long-press drag (DragSelectGesture) reports the day under the finger via
//  coordinate math over the grid's frame.
//

import SwiftUI

struct MonthGridView: View {
    let month: Date
    let calendar: Calendar
    let doneDays: Set<Date>
    /// Weekdays with a scheduled workout — marked ahead of today only (history shows fills).
    let scheduled: Set<Weekday>
    let selection: Set<Date>
    let footer: String
    let onTap: (Date) -> Void
    let onDragBegan: (Date) -> Void
    let onDragMoved: (Date) -> Void
    let onDragEnded: () -> Void

    private let cells: [Date]

    init(month: Date, calendar: Calendar, doneDays: Set<Date>, scheduled: Set<Weekday>,
         selection: Set<Date>, footer: String,
         onTap: @escaping (Date) -> Void, onDragBegan: @escaping (Date) -> Void,
         onDragMoved: @escaping (Date) -> Void, onDragEnded: @escaping () -> Void) {
        self.month = month
        self.calendar = calendar
        self.doneDays = doneDays
        self.scheduled = scheduled
        self.selection = selection
        self.footer = footer
        self.onTap = onTap
        self.onDragBegan = onDragBegan
        self.onDragMoved = onDragMoved
        self.onDragEnded = onDragEnded
        self.cells = CalendarMath.monthCells(containing: month, calendar: calendar)
    }

    private static let rowSpacing: CGFloat = 6
    @State private var gridSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 10) {
            weekdayHeader
            grid
            Text(footer)
                .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .cardSurface()
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.allCases) { day in
                Text(String(day.short.prefix(1)))
                    .font(.rounded(11, .heavy)).foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                  spacing: Self.rowSpacing) {
            ForEach(cells, id: \.self) { day in
                Button { onTap(day) } label: {
                    DayCellView(
                        number: calendar.component(.day, from: day),
                        inMonth: CalendarMath.isInMonth(day, of: month, calendar: calendar),
                        isToday: calendar.isDateInToday(day),
                        isDone: doneDays.contains(day),
                        isScheduledFuture: isScheduledFuture(day),
                        isSelected: selection.contains(day)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day))
                .accessibilityAddTraits(selection.contains(day) ? [.isButton, .isSelected] : .isButton)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { gridSize = $0 }
        .gesture(DragSelectGesture(
            onBegan: { if let day = day(at: $0) { onDragBegan(day) } },
            onMoved: { if let day = day(at: $0) { onDragMoved(day) } },
            onEnded: onDragEnded
        ))
    }

    /// Only days after today carry the "planned" dot — the past already shows its fills,
    /// and double-marking every scheduled weekday would bury the signal (the Apple/Garmin
    /// undifferentiated-marker complaint from the design bible).
    private func isScheduledFuture(_ day: Date) -> Bool {
        guard day > Date(), !calendar.isDateInToday(day) else { return false }
        return scheduled.contains(Weekday.from(day, calendar: calendar))
    }

    /// O(1) hit-test: 7 columns × 6 rows over the grid frame, spacing folded in so no
    /// point falls between cells.
    private func day(at point: CGPoint) -> Date? {
        guard gridSize.width > 0, gridSize.height > 0, cells.count == 42 else { return nil }
        let col = min(6, max(0, Int(point.x / (gridSize.width / 7))))
        let row = min(5, max(0, Int(point.y / (gridSize.height / 6))))
        return cells[row * 7 + col]
    }

    private func accessibilityLabel(for day: Date) -> String {
        var parts = [day.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if calendar.isDateInToday(day) { parts.insert("Today", at: 0) }
        if doneDays.contains(day) { parts.append("workout completed") }
        if isScheduledFuture(day) { parts.append("workout scheduled") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Day cell

/// One calendar day. One primary encoding per cell: accent-filled circle around the day
/// number = trained; 2 pt ring = today; 4 pt dot = scheduled future; soft chip = selected.
private struct DayCellView: View {
    let number: Int
    let inMonth: Bool
    let isToday: Bool
    let isDone: Bool
    let isScheduledFuture: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.accent : Color.clear)
                if isToday {
                    Circle().strokeBorder(Color.accent, lineWidth: 2)
                }
                Text("\(number)")
                    .font(.rounded(14, isDone ? .heavy : .semibold))
                    .foregroundStyle(numberColor)
                    .tabularNumbers()
            }
            .frame(width: 32, height: 32)
            Circle()
                .fill(isScheduledFuture ? Color.accent.opacity(0.55) : .clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentSoft : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(inMonth ? 1 : 0.35)
    }

    private var numberColor: Color {
        if isDone { return .white }
        return inMonth ? Color.textPrimary : Color.text3
    }
}
