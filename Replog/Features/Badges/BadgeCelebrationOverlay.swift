//
//  BadgeCelebrationOverlay.swift
//  Replog
//
//  The moment a badge lands.
//
//  Deliberately a bigger event than the end-of-workout confetti, and deliberately a
//  different shape of one: that celebration rains down, this one detonates outward. A
//  badge is rarer than a finished session, so it gets the louder moment — fireworks from
//  several origins, a shockwave, a medal that slams in and shakes on impact, a glint that
//  sweeps across it, and a haptic sequence timed to the visuals rather than one buzz.
//
//  Everything is native SwiftUI and drawn, like `CelebrationOverlay`: no animation assets,
//  no third-party packages.
//
//  The particle layout is generated once into state rather than computed in `body`. A
//  `random` call in a view body re-rolls on every redraw, which makes fireworks flicker
//  and re-aim mid-flight.
//
//  Respects Reduce Motion: the copy, the medal and the haptics all still land, but nothing
//  flies, spins or shakes.
//

import SwiftUI

struct BadgeCelebrationOverlay: View {
    let badges: [Badge]
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which badge is on screen when several were earned at once.
    @State private var index = 0
    @State private var bursts: [Firework] = []

    // Animation state, reset per badge.
    @State private var medalIn = false
    @State private var shockwave = false
    @State private var shake: CGFloat = 0
    @State private var glint = false
    @State private var textIn = false

    // Separate triggers so each kind of haptic can fire on its own schedule.
    @State private var softTick = 0
    @State private var heavyTick = 0
    @State private var successTick = 0

    private var badge: Badge? { badges[safe: index] }
    private var isLast: Bool { index >= badges.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            if !reduceMotion {
                ForEach(bursts) { firework in
                    FireworkBurstView(firework: firework)
                }
                .allowsHitTesting(false)
            }

            if let badge { card(badge) }
        }
        .task(id: index) { await runSequence() }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: softTick)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: heavyTick)
        .sensoryFeedback(.success, trigger: successTick)
    }

    // MARK: - The card

    private func card(_ badge: Badge) -> some View {
        VStack(spacing: 16) {
            Text(badges.count > 1 ? "Badge \(index + 1) of \(badges.count)" : "Badge unlocked")
                .font(.rounded(12, .heavy))
                .foregroundStyle(Color.accent)
                .opacity(textIn ? 1 : 0)

            medal(badge)

            VStack(spacing: 8) {
                Text("Congratulations!")
                    .font(.rounded(26, .black)).foregroundStyle(Color.textPrimary)
                Text("You earned \(badge.name).")
                    .font(.rounded(17, .heavy)).foregroundStyle(Color.accent)
                    .multilineTextAlignment(.center)
                Text(badge.meaning)
                    .font(.rounded(14, .semibold)).foregroundStyle(Color.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 12)

            PrimaryButton(title: isLast ? "Nice" : "Next") { advance() }
                .padding(.top, 2)
                .opacity(textIn ? 1 : 0)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous)
            .fill(Color.surface))
        .padding(.horizontal, 28)
        .scaleEffect(medalIn ? 1 : 0.86)
        .opacity(medalIn ? 1 : 0)
    }

    /// The medal itself: a shockwave ring, rotating rays behind it, the medal slamming in
    /// with an overshoot, a shake on impact, and a glint sweeping across the face.
    private func medal(_ badge: Badge) -> some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .strokeBorder(Color.accent.opacity(shockwave ? 0 : 0.85), lineWidth: 5)
                    .frame(width: 150, height: 150)
                    .scaleEffect(shockwave ? 2.1 : 0.5)

                MedalRays()
                    .fill(Color.accent.opacity(0.16))
                    .frame(width: 230, height: 230)
                    .rotationEffect(.degrees(medalIn ? 24 : -6))
                    .scaleEffect(medalIn ? 1 : 0.7)
                    .opacity(medalIn ? 1 : 0)
            }

            MedalView(badge: badge, earned: true, size: 132)
                .scaleEffect(medalIn ? 1 : 0.2)
                .rotationEffect(.degrees(medalIn ? 0 : -35))
                .offset(x: reduceMotion ? 0 : shake)
                .overlay {
                    if !reduceMotion { glintSweep }
                }
        }
        .frame(height: 200)
    }

    /// A specular highlight that travels across the medal once, the way light moves over
    /// something metal when you tilt it.
    private var glintSweep: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(width: 46, height: 210)
            .rotationEffect(.degrees(28))
            .offset(x: glint ? 130 : -130)
            .mask(MedalOutline(shape: badge?.shape ?? .circle).frame(width: 132, height: 132))
            .allowsHitTesting(false)
    }

    // MARK: - Choreography

    /// Runs the entrance: fireworks, the medal landing, the shake, the glint and the copy,
    /// with the haptics timed to the beats rather than fired all at once.
    private func runSequence() async {
        resetForNewBadge()

        guard !reduceMotion else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                medalIn = true
                textIn = true
            }
            successTick += 1
            return
        }

        bursts = Firework.volley(seed: index)

        // The medal flies in and lands hard.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { medalIn = true }
        softTick += 1

        try? await Task.sleep(for: .milliseconds(240))
        heavyTick += 1                                    // impact
        withAnimation(.easeOut(duration: 0.7)) { shockwave = true }
        await shakeImpact()

        withAnimation(.easeOut(duration: 0.45)) { textIn = true }
        successTick += 1

        // A pop per firework as it opens, so the haptics track what is on screen. Waits
        // are the gap to the *next* burst, not its absolute delay, or they compound and
        // the taps drift further behind the visuals with every one.
        var elapsed = 0.24
        for firework in bursts.sorted(by: { $0.delay < $1.delay }) {
            let gap = max(0, firework.delay - elapsed)
            try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            elapsed = max(elapsed, firework.delay)
            softTick += 1
        }

        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeInOut(duration: 0.75)) { glint = true }
    }

    /// A short decaying wobble, the way a struck object rings down rather than stopping dead.
    private func shakeImpact() async {
        let swings: [(CGFloat, Int)] = [(-14, 55), (11, 50), (-7, 45), (4, 40), (0, 40)]
        for (offset, milliseconds) in swings {
            withAnimation(.easeInOut(duration: Double(milliseconds) / 1000)) { shake = offset }
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
    }

    private func resetForNewBadge() {
        medalIn = false
        shockwave = false
        textIn = false
        glint = false
        shake = 0
        bursts = []
    }

    private func advance() {
        if isLast {
            onDone()
        } else {
            withAnimation(.easeIn(duration: 0.15)) { medalIn = false; textIn = false }
            index += 1
        }
    }
}

// MARK: - Fireworks

/// One burst: where it opens, when, and what colour. Particle directions are derived from
/// the index so a burst is stable for its whole flight.
struct Firework: Identifiable, Equatable {
    let id: Int
    /// Position as a fraction of the screen, so it works on any device size.
    let x: CGFloat
    let y: CGFloat
    let delay: Double
    let color: Color
    let particles: Int
    let reach: CGFloat

    private static let palette: [Color] = [
        .accent, Color(hex: "#FFC24B"), Color(hex: "#5AA9FF"),
        Color(hex: "#B36AFF"), Color(hex: "#43C08D"), Color(hex: "#FF7A4D"),
    ]

    /// A staggered volley across the screen. Deterministic per `seed`, so a second badge
    /// gets a different arrangement but neither one re-rolls mid-animation.
    static func volley(seed: Int) -> [Firework] {
        // A small integer hash: enough to scatter the layout without a real RNG, and
        // reproducible, which is what keeps the particles from re-aiming on redraw.
        func noise(_ n: Int) -> CGFloat {
            let value = (n &* 1103515245 &+ 12345) & 0x7FFF_FFFF
            return CGFloat(value % 1000) / 1000
        }
        return (0..<7).map { index in
            let n = seed &* 31 &+ index
            return Firework(
                // The id has to differ between volleys. Reusing 0...6 lets `ForEach`
                // recycle the views, so `onAppear` never fires again and the second
                // badge of a session gets no fireworks at all — just spent particles.
                id: seed &* 100 &+ index,
                x: 0.10 + noise(n) * 0.80,
                // Alternating bands above and below the card. Spread evenly over the
                // screen they mostly detonate behind it and are never seen.
                y: index.isMultiple(of: 2)
                    ? 0.05 + noise(n &+ 101) * 0.17
                    : 0.76 + noise(n &+ 101) * 0.17,
                delay: 0.10 + Double(index) * 0.16 + Double(noise(n &+ 202)) * 0.10,
                color: palette[(index &+ seed) % palette.count],
                particles: 16 + Int(noise(n &+ 303) * 8),
                reach: 100 + noise(n &+ 404) * 90
            )
        }
    }
}

/// Draws one burst: particles thrown radially outward, fading and falling slightly as they
/// go, plus a brief flash at the origin.
struct FireworkBurstView: View {
    let firework: Firework
    @State private var open = false

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width * firework.x, y: geo.size.height * firework.y)
            ZStack {
                Circle()
                    .fill(firework.color.opacity(open ? 0 : 0.9))
                    .frame(width: open ? 46 : 4, height: open ? 46 : 4)
                    .position(origin)
                    .blur(radius: 6)

                ForEach(0..<firework.particles, id: \.self) { index in
                    let angle = (Double(index) / Double(firework.particles)) * 2 * .pi
                    // Alternating reach gives the burst a ragged edge rather than a
                    // perfect ring, which is what real fireworks look like.
                    let reach = firework.reach * (index.isMultiple(of: 2) ? 1 : 0.72)
                    Circle()
                        .fill(firework.color)
                        .frame(width: 7, height: 7)
                        .position(
                            x: origin.x + (open ? cos(angle) * reach : 0),
                            // Gravity: the tail of the burst sags as it fades.
                            y: origin.y + (open ? sin(angle) * reach + 26 : 0)
                        )
                        .opacity(open ? 0 : 1)
                        .scaleEffect(open ? 0.5 : 1)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(firework.delay)) { open = true }
        }
    }
}

/// The rotating starburst behind the medal — long and short spokes alternating.
struct MedalRays: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<24 {
            let angle = (Double(index) / 24) * 2 * .pi
            let length = index.isMultiple(of: 2) ? outer : outer * 0.62
            let width = 0.035
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + cos(angle - width) * length,
                                     y: centre.y + sin(angle - width) * length))
            path.addLine(to: CGPoint(x: centre.x + cos(angle + width) * length,
                                     y: centre.y + sin(angle + width) * length))
            path.closeSubpath()
        }
        return path
    }
}
