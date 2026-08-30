//
//  BadgeCelebrationOverlay.swift
//  Replog
//
//  The moment a badge lands.
//
//  Deliberately a bigger event than the end-of-workout confetti, and deliberately a
//  different shape of one: that celebration rains down, this one detonates outward. A
//  badge is rarer than a finished session, so it gets the louder moment — fireworks from
//  several origins, a shockwave, and a haptic sequence timed to the visuals rather than
//  one buzz.
//
//  The medal itself does not simply appear. It tumbles in from above and SINKS slowly into
//  place, lands hard, then floats there — drifting a few points up and down while a slow
//  3D tilt catches the light across its face and a glow in its own palette breathes behind
//  it. Slow on purpose: the eye needs a beat to read what was won, and a thing that keeps
//  moving after it arrives reads as an object rather than a picture of one.
//
//  Everything is native SwiftUI and drawn, like `CelebrationOverlay`: no animation assets,
//  no third-party packages.
//
//  The particle layout is generated once into state rather than computed in `body`. A
//  `random` call in a view body re-rolls on every redraw, which makes fireworks flicker
//  and re-aim mid-flight.
//
//  Respects Reduce Motion: the copy, the medal and the haptics all still land, but nothing
//  flies, spins, tilts, floats or shakes.
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
    /// The medal has finished its descent and struck.
    @State private var landed = false
    @State private var shockwave = false
    @State private var shake: CGFloat = 0
    @State private var glint = false
    @State private var textIn = false
    /// The three "it is still alive" loops, started after the landing and left running.
    @State private var floating = false
    @State private var tilting = false
    @State private var glowing = false

    // Separate triggers so each kind of haptic can fire on its own schedule.
    @State private var softTick = 0
    @State private var heavyTick = 0
    @State private var successTick = 0

    private var badge: Badge? { badges[safe: index] }
    private var isLast: Bool { index >= badges.count - 1 }
    /// The medal's own colours, so the glow belongs to the badge rather than to the app.
    private var palette: MedalPalette { MedalPalette.named(badge?.palette ?? "bronze") }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            if !reduceMotion {
                ForEach(bursts) { firework in
                    FireworkBurstView(firework: firework)
                }
                .allowsHitTesting(false)
            }

            if let badge {
                // The card fits every current badge at the largest accessibility text size,
                // but "fits today" is not a guarantee: one longer `meaning`, one smaller
                // device, and the button that ends the celebration is off-screen with no
                // way to scroll to it. The scrolling copy is used only when it has to be.
                ViewThatFits(in: .vertical) {
                    card(badge)
                    ScrollView { card(badge) }.scrollIndicators(.hidden)
                }
            }
        }
        // The celebration owns the screen, so VoiceOver should not be able to wander into
        // the Today screen behind the scrim — sighted users cannot, and the scrim swallows
        // their taps.
        .accessibilityAddTraits(.isModal)
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
        .scaleEffect(landed ? 1 : 0.86)
        .opacity(landed ? 1 : 0)
    }

    /// The medal: a glow breathing in its own colours, a shockwave ring, rotating rays, the
    /// medal sinking in and striking, then floating and tilting in 3D with a glint sweeping
    /// across its face.
    private func medal(_ badge: Badge) -> some View {
        ZStack {
            if !reduceMotion {
                glow

                Circle()
                    .strokeBorder(Color.accent.opacity(shockwave ? 0 : 0.85), lineWidth: 5)
                    .frame(width: 150, height: 150)
                    .scaleEffect(shockwave ? 2.1 : 0.5)

                MedalRays()
                    .fill(Color.accent.opacity(0.16))
                    .frame(width: 230, height: 230)
                    .rotationEffect(.degrees(landed ? 24 : -6))
                    .scaleEffect(landed ? 1 : 0.7)
                    .opacity(landed ? 1 : 0)
            }

            MedalView(badge: badge, earned: true, size: 132)
                .shadow(color: reduceMotion ? .clear : palette.accent.opacity(glowing ? 0.75 : 0.35),
                        radius: glowing ? 26 : 14)
                // The descent: it arrives from above, tumbling, and settles rather than pops.
                .scaleEffect(landed ? 1 : 0.55)
                .offset(y: descentOffset)
                .rotation3DEffect(.degrees(landed ? 0 : -150),
                                  axis: (x: 0.1, y: 1, z: 0), perspective: 0.55)
                // ...and once landed it never quite stops: a slow tilt, a slow drift.
                .rotation3DEffect(.degrees(tiltDegrees),
                                  axis: (x: 0.22, y: 1, z: 0), perspective: 0.65)
                .offset(x: reduceMotion ? 0 : shake, y: floatOffset)
                .overlay {
                    if !reduceMotion { glintSweep }
                }
        }
        .frame(height: 200)
    }

    /// The halo. A radial wash in the medal's own palette that breathes, which is what makes
    /// the plate read as lit rather than printed.
    private var glow: some View {
        Circle()
            .fill(RadialGradient(colors: [palette.accent.opacity(0.55),
                                          palette.body.opacity(0.28), .clear],
                                 center: .center, startRadius: 8, endRadius: 130))
            .frame(width: 280, height: 280)
            .blur(radius: 14)
            .scaleEffect(glowing ? 1.10 : 0.86)
            .opacity(landed ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// How far above its resting place the medal still is. Reduce Motion has no descent.
    private var descentOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return landed ? 0 : -120
    }

    /// The idle drift, once it has landed. Zero until then so it cannot fight the descent.
    private var floatOffset: CGFloat {
        guard !reduceMotion, landed else { return 0 }
        return floating ? -8 : 8
    }

    /// The idle 3D tilt, once it has landed.
    private var tiltDegrees: Double {
        guard !reduceMotion, landed else { return 0 }
        return tilting ? 13 : -13
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

    /// Runs the entrance: fireworks, the medal sinking in and striking, the shake, the glint
    /// and the copy, with the haptics timed to the beats rather than fired all at once.
    private func runSequence() async {
        // No badge means a scrim with no card and no button: nothing to dismiss it with.
        // `SessionCompletion` never raises this stage empty, but a component that can trap
        // the athlete is a bug regardless of what its callers happen to do today.
        guard badge != nil else {
            onDone()
            return
        }

        resetForNewBadge()

        guard !reduceMotion else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                landed = true
                textIn = true
            }
            successTick += 1
            return
        }

        bursts = Firework.volley(seed: index)

        // The descent. Slow, and slightly springy at the end so it settles rather than stops
        // dead — with a ladder of soft taps underneath it that tightens as it falls, which is
        // what makes the landing feel earned rather than announced.
        withAnimation(.spring(response: 0.95, dampingFraction: 0.62)) { landed = true }
        await descentTicks()

        heavyTick += 1                                    // impact
        withAnimation(.easeOut(duration: 0.7)) { shockwave = true }
        await shakeImpact()

        // It has arrived: light it, and leave it alive.
        startIdleMotion()

        withAnimation(.easeOut(duration: 0.45)) { textIn = true }
        successTick += 1

        // A pop per firework as it opens, so the haptics track what is on screen. Waits
        // are the gap to the *next* burst, not its absolute delay, or they compound and
        // the taps drift further behind the visuals with every one.
        var elapsed = 0.68
        for firework in bursts.sorted(by: { $0.delay < $1.delay }) {
            let gap = max(0, firework.delay - elapsed)
            try? await Task.sleep(for: .milliseconds(Int(gap * 1000)))
            elapsed = max(elapsed, firework.delay)
            softTick += 1
        }

        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeInOut(duration: 0.75)) { glint = true }
    }

    /// Soft taps under the falling medal, closer together as it nears the floor. Together
    /// they last about as long as the descent, so the heavy strike lands on the impact.
    private func descentTicks() async {
        for gap in [170, 150, 130, 110, 90] {
            softTick += 1
            try? await Task.sleep(for: .milliseconds(gap))
        }
    }

    /// The three loops that keep a landed medal alive. Started once, left running: SwiftUI
    /// keeps a `repeatForever` animation going for as long as the view is on screen.
    private func startIdleMotion() {
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            floating = true
        }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
            tilting = true
        }
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
            glowing = true
        }
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
        // Without an explicit no-animation reset the running `repeatForever` loops carry
        // straight over onto the next badge, which then floats before it has landed.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            landed = false
            shockwave = false
            textIn = false
            glint = false
            floating = false
            tilting = false
            glowing = false
            shake = 0
            bursts = []
        }
    }

    private func advance() {
        if isLast {
            onDone()
        } else {
            withAnimation(.easeIn(duration: 0.15)) { landed = false; textIn = false }
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
