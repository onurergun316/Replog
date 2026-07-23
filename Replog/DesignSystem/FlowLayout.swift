//
//  FlowLayout.swift
//  Replog
//
//  A simple wrapping layout for chips/pills (left-to-right, wrapping to new rows).
//
//  Measuring and placing share one `rows(...)` pass. They used to duplicate the wrap
//  arithmetic against two different widths — `proposal.width` when measuring, `bounds`
//  when placing — so an unspecified proposal measured every chip onto a single row while
//  placement wrapped onto three. The container reserved one row's height and clipped the
//  rest, which is how the muscle legend lost its last line.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Chips grouped into rows that fit `maxWidth`, with each row's height.
    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [(items: [CGSize], height: CGFloat)] {
        var rows: [(items: [CGSize], height: CGFloat)] = []
        var current: [CGSize] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Width the row would occupy with this chip added — spacing only *between*
            // chips, which is what placement does too.
            let projected = current.isEmpty ? size.width : rowWidth + spacing + size.width
            if projected > maxWidth, !current.isEmpty {
                rows.append((current, rowHeight))
                current = [size]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                current.append(size)
                rowWidth = projected
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !current.isEmpty { rows.append((current, rowHeight)) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unspecified width must not mean "infinitely wide" — that measures one row
        // and under-reports the height by however many rows actually get placed.
        let maxWidth = proposal.width ?? proposal.replacingUnspecifiedDimensions().width
        let rows = rows(subviews, maxWidth: maxWidth)
        guard !rows.isEmpty else { return .zero }

        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(rows.count - 1)
        let width = rows
            .map { $0.items.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, $0.items.count - 1)) }
            .max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(subviews, maxWidth: bounds.width)
        var index = subviews.startIndex
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for size in row.items {
                guard index < subviews.endIndex else { return }
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
                index = subviews.index(after: index)
            }
            y += row.height + spacing
        }
    }
}
