//
//  WeekStripView.swift
//  Replog
//
//  The Sun…Sat calendar strip on Today: today is ringed in accent, completed days
//  are filled accent with a check, and a scheduled day carries a dot. When `onSelect`
//  is supplied the cells become buttons that pick which day Today is showing — the
//  selected day gets a soft accent chip so it reads independently of the today ring.
//
//  The strip pages horizontally through weeks. One page is exactly seven days wide, so
//  a swipe always lands on a whole week rather than scrolling days past the edge, and
//  the window it can reach comes from `StreakCalendar.weekWindow`.
//

import SwiftUI

struct WeekStripView: View {
    /// The weeks the strip can reach, as offsets from the current week (0 = this week).
    let weekOffsets: [Int]
    /// The seven cells for a given week offset.
    let cells: (Int) -> [DayCell]
    /// Days that have a workout scheduled — marked with a dot so the strip shows the
    /// week's shape, not just what's been done.
    var scheduled: Set<Weekday> = []
    /// The day Today is currently showing. Nil leaves the strip purely informational.
    var selected: Weekday?
    /// Which week is on screen. Two-way so the caller can snap back to this week.
    @Binding var weekOffset: Int
    var onSelect: ((Weekday) -> Void)?

    /// `scrollPosition` needs an optional binding; kept in sync with `weekOffset` so a
    /// programmatic jump (the "Today" chip) scrolls, and a swipe reports back.
    @State private var visiblePage: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(weekOffsets, id: \.self) { offset in
                    week(offset)
                        .containerRelativeFrame(.horizontal)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visiblePage, anchor: .center)
        .scrollIndicators(.hidden)
        // The chips already read as one row; clipping would cut their soft background.
        .scrollClipDisabled()
        .frame(height: stripHeight)
        .onAppear { visiblePage = weekOffset }
        .onChange(of: weekOffset) { _, new in
            guard visiblePage != new else { return }
            withAnimation(.snappy) { visiblePage = new }
        }
        .onChange(of: visiblePage) { _, new in
            guard let new, new != weekOffset else { return }
            weekOffset = new
        }
        .sensoryFeedback(.selection, trigger: weekOffset)
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// Seven cells plus the week caption. Fixed so paging never resizes the row.
    private var stripHeight: CGFloat { 92 }

    private func week(_ offset: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(cells(offset)) { cell in
                    if let onSelect {
                        Button { onSelect(cell.weekday) } label: { cellBody(cell) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: cell))
                            .accessibilityAddTraits(isSelected(cell, in: offset) ? [.isButton, .isSelected] : .isButton)
                    } else {
                        cellBody(cell)
                    }
                }
            }
            // Only when browsing: on this week the strip's today ring says it already.
            Text(offset == 0 ? " " : StreakCalendar.weekLabel(offset: offset))
                .font(.rounded(11, .heavy))
                .foregroundStyle(Color.text3)
        }
    }

    /// The selection chip belongs to the week actually being browsed — otherwise every
    /// page would highlight the same weekday and the pager would look stuck.
    private func isSelected(_ cell: DayCell, in offset: Int) -> Bool {
        offset == weekOffset && cell.weekday == selected
    }

    private func cellBody(_ cell: DayCell) -> some View {
        let selectedCell = isSelected(cell, in: weekOffset)
        return VStack(spacing: 6) {
            Text(String(cell.weekday.short.prefix(1)))
                .font(.rounded(11, .heavy))
                .foregroundStyle(selectedCell ? Color.accent : Color.text3)
            circle(for: cell)
            Circle()
                .fill(scheduled.contains(cell.weekday) ? Color.accent.opacity(0.55) : .clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selectedCell ? Color.accentSoft : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func circle(for cell: DayCell) -> some View {
        ZStack {
            Circle()
                .fill(cell.isCompleted ? Color.accent : Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        cell.isToday ? Color.accent : Color.border,
                        lineWidth: cell.isToday ? 2 : 1
                    )
                )
            if cell.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func accessibilityLabel(for cell: DayCell) -> String {
        var parts = [cell.isToday ? "Today, \(cell.weekday.displayName)" : cell.weekday.displayName]
        if scheduled.contains(cell.weekday) { parts.append("workout scheduled") }
        if cell.isCompleted { parts.append("completed") }
        return parts.joined(separator: ", ")
    }
}
