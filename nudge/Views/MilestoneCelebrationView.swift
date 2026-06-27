import SwiftUI

struct MilestoneCelebrationView: View {
    let streak: Int
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private var emoji: String {
        switch streak {
        case 100...: return "🏆"
        case 30...:  return "⚡"
        default:     return "🔥"
        }
    }

    private var headline: String {
        "\(streak)-day streak!"
    }

    private var subtext: String {
        switch streak {
        case 100...: return "100 days. That's not a habit — that's a lifestyle."
        case 30...:  return "A full month of consistent movement. You're unstoppable."
        default:     return "Seven days straight. Momentum is building."
        }
    }

    var body: some View {
        ZStack {
            ConfettiLayer()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text(emoji)
                    .font(.system(size: 80))
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.55), value: appeared)

                VStack(spacing: 10) {
                    Text(headline)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)

                    Text(subtext)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Keep it going")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .nocturnePrimaryButton(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.35), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Simple confetti particles

private struct ConfettiLayer: View {
    private let particles: [ConfettiParticle] = (0..<50).map { _ in ConfettiParticle() }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                ConfettiParticleView(particle: p, containerWidth: geo.size.width, containerHeight: geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat = CGFloat.random(in: 0...1)
    let size: CGFloat = CGFloat.random(in: 6...12)
    let color: Color = [Color.red, .orange, .yellow, .green, .blue, .purple, .pink].randomElement()!
    let delay: Double = Double.random(in: 0...1.2)
    let duration: Double = Double.random(in: 1.8...3.0)
    let rotation: Double = Double.random(in: 0...360)
    let isCircle: Bool = Bool.random()
}

private struct ConfettiParticleView: View {
    let particle: ConfettiParticle
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    @State private var dropped = false

    var body: some View {
        Group {
            if particle.isCircle {
                Circle().fill(particle.color)
            } else {
                Rectangle().fill(particle.color).rotationEffect(.degrees(particle.rotation))
            }
        }
        .frame(width: particle.size, height: particle.size)
        .position(
            x: containerWidth * particle.x,
            y: dropped ? containerHeight + 20 : -20
        )
        .opacity(dropped ? 0 : 0.85)
        .onAppear {
            withAnimation(
                .easeIn(duration: particle.duration)
                .delay(particle.delay)
            ) {
                dropped = true
            }
        }
    }
}
