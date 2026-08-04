//
//  MedalView.swift
//  Replog
//
//  Badges, drawn rather than shipped as images.
//
//  Fifty-odd medals as artwork would be megabytes of assets that cannot be restyled and
//  cannot adapt to dark mode. Drawn from a shape, a motif and a palette they are a few
//  kilobytes of code, sharp at any size, and a new badge costs three enum cases rather than
//  a trip to a designer.
//
//  The look is a struck medal of honour with no ribbon: a geometric outline, a bevelled
//  rim, and an abstract device inside. Two or three colours per medal, taken from curated
//  palettes rather than picked by hand, so fifty of them on one grid still read as a set.
//
//  Locked medals draw the same geometry as a flat grey silhouette, so the shape of what is
//  missing is visible without giving away more than the hint does.
//

import SwiftUI

// MARK: - Palettes

/// A medal's two or three colours, resolved. `body` fills the plate, `accent` draws the
/// device, and `detail` is the highlight along the bevel. The tokens themselves live in
/// `MedalPalettes` in the domain, so the badge catalogue can be validated without SwiftUI.
struct MedalPalette: Sendable, Hashable {
    var id: String
    var body: Color
    var accent: Color
    var detail: Color

    static func named(_ id: String) -> MedalPalette {
        let hex = MedalPalettes.triple(id)
        return MedalPalette(id: id, body: Color(hex: hex.body),
                            accent: Color(hex: hex.accent), detail: Color(hex: hex.detail))
    }
}

// MARK: - The medal

/// One badge, drawn. `earned` false renders the locked silhouette.
struct MedalView: View {
    let badge: Badge
    var earned: Bool = true
    var size: CGFloat = 72

    private var palette: MedalPalette { MedalPalette.named(badge.palette) }

    var body: some View {
        ZStack {
            plate
            if earned {
                MedalMotifShape(motif: badge.motif)
                    .fill(palette.accent)
                    .frame(width: size * 0.52, height: size * 0.52)
                MedalMotifShape(motif: badge.motif)
                    .fill(palette.detail.opacity(0.55))
                    .frame(width: size * 0.52, height: size * 0.52)
                    .offset(x: -size * 0.012, y: -size * 0.012)
                    .blendMode(.screen)
            } else {
                MedalMotifShape(motif: badge.motif)
                    .fill(Color.text3.opacity(0.35))
                    .frame(width: size * 0.52, height: size * 0.52)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(earned ? "\(badge.name), earned" : "\(badge.name), locked")
    }

    private var outline: MedalOutline { MedalOutline(shape: badge.shape) }

    /// The plate itself: a bevel gradient running top-left to bottom-right, which is what
    /// makes a flat fill read as struck metal.
    private var plateFill: AnyShapeStyle {
        guard earned else { return AnyShapeStyle(Color.surface2) }
        let gradient = LinearGradient(colors: [palette.detail, palette.body],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        return AnyShapeStyle(gradient)
    }

    private var rimColor: Color { earned ? palette.accent.opacity(0.85) : Color.border }

    private var innerRingColor: Color {
        earned ? palette.detail.opacity(0.6) : Color.border.opacity(0.6)
    }

    /// The struck plate: filled outline, hairline rim, and the inner ring every real medal
    /// has. Broken into named pieces because one chained expression here is more than the
    /// type checker will solve in reasonable time.
    private var plate: some View {
        outline
            .fill(plateFill)
            .overlay(rim)
            .overlay(innerRing)
            .frame(width: size, height: size)
            .shadow(color: earned ? palette.body.opacity(0.35) : .clear,
                    radius: size * 0.08, x: 0, y: size * 0.03)
    }

    private var rim: some View {
        outline.strokeBorder(rimColor, lineWidth: max(1, size * 0.035))
    }

    private var innerRing: some View {
        outline.inset(by: size * 0.13)
            .strokeBorder(innerRingColor, lineWidth: max(0.5, size * 0.014))
    }
}

// MARK: - Outlines

/// The medal's silhouette. `InsettableShape` so the inner ring is the same geometry inset,
/// which is what makes a bevel look struck rather than drawn twice.
struct MedalOutline: InsettableShape {
    var shape: BadgeShape
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> MedalOutline {
        MedalOutline(shape: shape, insetAmount: insetAmount + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        switch shape {
        case .circle:
            return Path(ellipseIn: r)
        case .oval:
            return Path(ellipseIn: r.insetBy(dx: r.width * 0.12, dy: 0))
        case .rect:
            return Path(roundedRect: r.insetBy(dx: r.width * 0.06, dy: r.height * 0.02),
                        cornerRadius: r.width * 0.16, style: .continuous)
        case .triangle:
            return polygon(sides: 3, in: r, rotation: -.pi / 2, cornerFraction: 0.10)
        case .hexagon:
            return polygon(sides: 6, in: r, rotation: -.pi / 2, cornerFraction: 0.06)
        case .diamond:
            return polygon(sides: 4, in: r, rotation: -.pi / 2, cornerFraction: 0.06)
        case .shield:
            return shieldPath(in: r)
        case .starburst:
            return starPath(points: 8, in: r)
        }
    }

    /// A regular polygon with softened corners, so a triangle at 64pt does not look like a
    /// razor blade next to a circle.
    private func polygon(sides: Int, in rect: CGRect, rotation: CGFloat,
                         cornerFraction: CGFloat) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { index -> CGPoint in
            let angle = rotation + (CGFloat(index) / CGFloat(sides)) * 2 * .pi
            return CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
        }
        var path = Path()
        let radiusOfCorner = radius * cornerFraction
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            if index == 0 { path.move(to: midpoint(current, next)) }
            path.addArc(tangent1End: next, tangent2End: midpoint(next, points[(index + 2) % points.count]),
                        radius: radiusOfCorner)
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// A crest: square shoulders, curved sides, a point at the bottom.
    private func shieldPath(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.02)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.10, y: r.minY),
                          control: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - r.width * 0.10, y: r.minY))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.10),
                          control: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.52))
        path.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY),
                          control: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.52),
                          control: CGPoint(x: r.minX, y: r.maxY - r.height * 0.10))
        path.closeSubpath()
        return path
    }

    /// An eight-point star with a generous inner radius, so it reads as a decoration rather
    /// than a spiky asterisk.
    private func starPath(points: Int, in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.74
        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + (CGFloat(index) / CGFloat(points * 2)) * 2 * .pi
            let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Motifs

/// The abstract device struck into the middle of the plate. Deliberately geometric: these
/// have to stay legible at 28pt in a grid.
struct MedalMotifShape: Shape {
    var motif: BadgeMotif

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        switch motif {
        case .chevrons:
            for index in 0..<3 {
                let y = h * (0.18 + Double(index) * 0.26)
                path.addPath(stroke(from: CGPoint(x: w * 0.15, y: y + h * 0.16),
                                    via: CGPoint(x: w * 0.5, y: y),
                                    to: CGPoint(x: w * 0.85, y: y + h * 0.16),
                                    width: h * 0.10))
            }
        case .rays:
            for index in 0..<8 {
                let angle = (Double(index) / 8) * 2 * .pi - .pi / 2
                path.addPath(stroke(from: CGPoint(x: w / 2 + cos(angle) * w * 0.16,
                                                  y: h / 2 + sin(angle) * h * 0.16),
                                    to: CGPoint(x: w / 2 + cos(angle) * w * 0.5,
                                                y: h / 2 + sin(angle) * h * 0.5),
                                    width: h * 0.09))
            }
            path.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.38, width: w * 0.24, height: h * 0.24))
        case .bars:
            for index in 0..<4 {
                let barHeight = h * (0.28 + Double(index) * 0.20)
                path.addRoundedRect(in: CGRect(x: w * (0.10 + Double(index) * 0.22),
                                               y: h - barHeight,
                                               width: w * 0.14, height: barHeight),
                                    cornerSize: CGSize(width: w * 0.04, height: w * 0.04))
            }
        case .laurel:
            for side in [-1.0, 1.0] {
                for index in 0..<4 {
                    let t = 0.16 + Double(index) * 0.21
                    let x = w * 0.5 + side * w * (0.16 + Double(index) * 0.055)
                    path.addEllipse(in: CGRect(x: x - w * 0.09, y: h * t,
                                               width: w * 0.18, height: h * 0.13))
                }
            }
        case .concentricRings:
            for index in 0..<3 {
                let inset = w * (0.06 + Double(index) * 0.14)
                path.addPath(ring(in: rect.insetBy(dx: inset, dy: inset), width: h * 0.075))
            }
        case .crossedBars:
            path.addPath(stroke(from: CGPoint(x: w * 0.12, y: h * 0.82),
                                to: CGPoint(x: w * 0.88, y: h * 0.18), width: h * 0.13))
            path.addPath(stroke(from: CGPoint(x: w * 0.12, y: h * 0.18),
                                to: CGPoint(x: w * 0.88, y: h * 0.82), width: h * 0.13))
        case .ascendingSteps:
            for index in 0..<4 {
                let stepHeight = h * (0.22 + Double(index) * 0.18)
                path.addRect(CGRect(x: w * Double(index) * 0.25, y: h - stepHeight,
                                    width: w * 0.22, height: stepHeight))
            }
        case .flame:
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.06))
            path.addQuadCurve(to: CGPoint(x: w * 0.84, y: h * 0.62),
                              control: CGPoint(x: w * 0.86, y: h * 0.24))
            path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.96),
                              control: CGPoint(x: w * 0.82, y: h * 0.92))
            path.addQuadCurve(to: CGPoint(x: w * 0.16, y: h * 0.62),
                              control: CGPoint(x: w * 0.18, y: h * 0.92))
            path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.06),
                              control: CGPoint(x: w * 0.14, y: h * 0.24))
            path.closeSubpath()
        case .wave:
            for index in 0..<3 {
                let y = h * (0.24 + Double(index) * 0.26)
                var line = Path()
                line.move(to: CGPoint(x: w * 0.08, y: y))
                line.addCurve(to: CGPoint(x: w * 0.92, y: y),
                              control1: CGPoint(x: w * 0.36, y: y - h * 0.20),
                              control2: CGPoint(x: w * 0.64, y: y + h * 0.20))
                path.addPath(line.strokedPath(.init(lineWidth: h * 0.09, lineCap: .round)))
            }
        case .grid:
            for row in 0..<3 {
                for column in 0..<3 {
                    path.addRoundedRect(in: CGRect(x: w * (0.10 + Double(column) * 0.30),
                                                   y: h * (0.10 + Double(row) * 0.30),
                                                   width: w * 0.20, height: h * 0.20),
                                        cornerSize: CGSize(width: w * 0.05, height: w * 0.05))
                }
            }
        case .orbit:
            path.addPath(ring(in: rect.insetBy(dx: w * 0.06, dy: h * 0.24), width: h * 0.075))
            path.addPath(ring(in: rect.insetBy(dx: w * 0.24, dy: h * 0.06), width: h * 0.075))
            path.addEllipse(in: CGRect(x: w * 0.40, y: h * 0.40, width: w * 0.20, height: h * 0.20))
        case .peak:
            path.move(to: CGPoint(x: w * 0.06, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.56))
            path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.88))
            path.closeSubpath()
        }
        return path
    }

    private func ring(in rect: CGRect, width: CGFloat) -> Path {
        Path(ellipseIn: rect).strokedPath(.init(lineWidth: width))
    }

    private func stroke(from: CGPoint, to: CGPoint, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path.strokedPath(.init(lineWidth: width, lineCap: .round))
    }

    private func stroke(from: CGPoint, via: CGPoint, to: CGPoint, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: via)
        path.addLine(to: to)
        return path.strokedPath(.init(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
