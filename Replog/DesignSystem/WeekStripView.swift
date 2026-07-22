//
//  WeekStripView.swift
//  Replog
//
//  The Sun…Sat calendar strip on Today: today is ringed in accent, completed days
//  are filled accent with a check, and a scheduled day carries a dot. When `onSelect`
//  is supplied the cells become buttons that pick which day Today is showing — the
//  selected day gets a soft accent chip so it reads independently of the today ring.
//

import SwiftUI

struct WeekStripView: View {
    let cells: [DayCell]
    /// Days that have a workout scheduled — marked with a dot so the strip shows the
    /// week's shape, not just what's been done.
    var scheduled: Set<Weekday> = []
    /// The day Today is currently showing. Nil leaves the strip purely informational.
    var selected: Weekday?
    var onSelect: ((Weekday) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(cells) { cell in
                if let onSelect {
                    Button { onSelect(cell.weekday) } label: { cellBody(cell) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: cell))
                        .accessibilityAddTraits(cell.weekday == selected ? [.isButton, .isSelected] : .isButton)
                } else {
                    cellBody(cell)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func cellBody(_ cell: DayCell) -> some View {
        let isSelected = cell.weekday == selected
        return VStack(spacing: 6) {
            Text(String(cell.weekday.short.prefix(1)))
                .font(.rounded(11, .heavy))
                .foregroundStyle(isSelected ? Color.accent : Color.text3)
            circle(for: cell)
            Circle()
                .fill(scheduled.contains(cell.weekday) ? Color.accent.opacity(0.55) : .clear)
                .frame(width: 4, height: 4)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentSoft : .clear)
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
