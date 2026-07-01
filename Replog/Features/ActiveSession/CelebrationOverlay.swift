//
//  CelebrationOverlay.swift
//  Replog
//
//  A Duolingo-style "you finished!" moment: a burst of confetti, a spring-popped
//  trophy, a summary, and success haptics — shown when every set of a workout is
//  complete. Fully native SwiftUI (no animation assets / third-party packages).
//

import SwiftUI

struct CelebrationOverlay: View {
    let sets: Int
    let exercises: Int
    let onFinish: () -> Void
    let onKeepGoing: () -> Void

    @State private var pop = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onKeepGoing() }

            ConfettiView()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accent, Color.accentPress],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 108, height: 108)
                        .shadow(color: Color.accent.opacity(0.4), radius: 18, y: 8)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
                }
                .scaleEffect(pop ? 1 : 0.3)
                .rotationEffect(.degrees(pop ? 0 : -20))

                Text("Workout Complete!")
                    .font(.rounded(24, .black)).foregroundStyle(Color.textPrimary)
                Text("You crushed all \(sets) \(sets == 1 ? "set" : "sets") across \(exercises) \(exercises == 1 ? "exercise" : "exercises"). Great work.")
                    .font(.rounded(14, .semibold)).foregroundStyle(Color.text2)
                    .multilineTextAlignment(.center)

                PrimaryButton(title: "Finish & Save") { onFinish() }
                    .padding(.top, 4)
                Button("Keep going") { onKeepGoing() }
                    .font(.rounded(14, .heavy)).foregroundStyle(Color.text2)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous).fill(Color.surface))
            .padding(.horizontal, 32)
            .scaleEffect(pop ? 1 : 0.8)
            .opacity(pop ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true } }
        .sensoryFeedback(.success, trigger: pop)
    }
}

// MARK: - Confetti

private struct ConfettiView: View {
    private let pieces = 70
    private let palette: [Color] = [.accent, .accentPress, .up, .down,
                                    Color(hex: "#FFC24B"), Color(hex: "#5AA9FF"), Color(hex: "#B36AFF")]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieces, id: \.self) { i in
                    ConfettiPiece(
                        color: palette[i % palette.count],
                        startX: CGFloat.random(in: 0...geo.size.width),
                        travel: geo.size.height + 80,
                        delay: Double.random(in: 0...0.5),
                        duration: Double.random(in: 1.6...3.0),
                        spin: Double.random(in: -540...540),
                        width: CGFloat.random(in: 6...11),
                        height: CGFloat.random(in: 9...16)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ConfettiPiece: View {
    let color: Color
    let startX: CGFloat
    let travel: CGFloat
    let delay: Double
    let duration: Double
    let spin: Double
    let width: CGFloat
    let height: CGFloat

    @State private var fall = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(fall ? spin : 0))
            .position(x: startX, y: fall ? travel : -40)
            .opacity(fall ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(delay)) { fall = true }
            }
    }
}
