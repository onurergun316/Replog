//
//  Sparkline.swift
//  Replog
//
//  A tiny inline trend line for Progress rows. Pure Path drawing (cheap).
//

import SwiftUI

struct Sparkline: View {
    let values: [Int]
    var color: Color = .accent

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                line(in: geo.size)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                // Flat baseline for sparse data.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func line(in size: CGSize) -> Path {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(1, maxV - minV)
        let stepX = size.width / CGFloat(values.count - 1)

        return Path { p in
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - (CGFloat(v - minV) / CGFloat(range)) * size.height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
