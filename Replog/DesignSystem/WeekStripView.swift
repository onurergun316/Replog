//
//  WeekStripView.swift
//  Replog
//
//  The Sun…Sat calendar strip on Today: today is ringed in accent, completed days
//  are filled accent with a check.
//

import SwiftUI

struct WeekStripView: View {
    let cells: [DayCell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(cells) { cell in
                VStack(spacing: 6) {
                    Text(String(cell.weekday.short.prefix(1)))
                        .font(.rounded(11, .heavy))
                        .foregroundStyle(Color.text3)
                    circle(for: cell)
                }
                .frame(maxWidth: .infinity)
            }
        }
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
}
